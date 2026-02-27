/**
 * RWR Group Slack LMS — Google Apps Script: Lesson Edit Detector
 * ==============================================================
 * Detects edits to the Lessons tab in the Google Sheet and notifies
 * Agent 16 (Lesson Edit Detector) in real time.
 *
 * SETUP INSTRUCTIONS:
 * ===================
 * 1. In Google Sheets: Extensions > Apps Script
 * 2. Paste this entire file, replacing any existing content
 * 3. Set your webhook URL in Script Properties:
 *       File > Project Properties > Script Properties
 *       Key:   AGENT_16_WEBHOOK_URL
 *       Value: https://your-domain.com/webhook/lesson-edit-detect
 * 4. Run setupTriggers() once from the toolbar (Run menu > setupTriggers)
 * 5. Authorize when prompted (required for trigger installation)
 * 6. Run testWebhook() to verify connectivity to Agent 16
 *
 * SHEET STRUCTURE REQUIREMENTS:
 * ==============================
 * - "Lessons" tab: Row 1 = headers, Column A = lesson_id (e.g. M01-W01-L01)
 * - "Checksums" tab: Used by this script to track row checksums.
 *   Created automatically if it doesn't exist.
 *
 * NOTES:
 * ======
 * - The onEdit(e) trigger fires for any cell edit in the spreadsheet.
 *   It filters to only process edits in the "Lessons" tab.
 * - Checksums are stored in the "Checksums" tab keyed by lesson_id.
 * - If the checksum has not changed (e.g. a cell was edited back to its
 *   original value), the webhook is NOT called.
 */

// ─── Configuration ────────────────────────────────────────────────────────────
var LESSONS_TAB_NAME = 'Lessons';
var CHECKSUMS_TAB_NAME = 'Checksums';
var LESSON_ID_COLUMN = 1; // Column A = lesson_id


// ─── Main onEdit trigger ──────────────────────────────────────────────────────

/**
 * Called automatically by Google Sheets whenever any cell is edited.
 * Filters to the Lessons tab and sends change notifications to Agent 16.
 *
 * @param {GoogleAppsScript.Events.SheetsOnEdit} e - The edit event object
 */
function onEdit(e) {
  try {
    var sheet = e.range.getSheet();

    // Only process edits in the Lessons tab
    if (sheet.getName() !== LESSONS_TAB_NAME) {
      return;
    }

    var editedRow = e.range.getRow();

    // Skip the header row
    if (editedRow <= 1) {
      return;
    }

    // Get the lesson_id from column A of the edited row
    var lessonID = sheet.getRange(editedRow, LESSON_ID_COLUMN).getValue();
    if (!lessonID || String(lessonID).trim() === '') {
      Logger.log('onEdit: No lesson_id in row ' + editedRow + ' — skipping');
      return;
    }

    lessonID = String(lessonID).trim();

    // Get all headers from row 1
    var lastCol = sheet.getLastColumn();
    var headers = sheet.getRange(1, 1, 1, lastCol).getValues()[0];

    // Get the full row values for checksumming
    var rowValues = sheet.getRange(editedRow, 1, 1, lastCol).getValues()[0];

    // Compute checksum of the full row
    var rowString = rowValues.join('|');
    var newChecksum = computeChecksum(rowString);

    // Compare with stored checksum
    var storedChecksum = getStoredChecksum(lessonID);
    if (storedChecksum === newChecksum) {
      Logger.log('onEdit: Checksum unchanged for ' + lessonID + ' — no notification sent');
      return;
    }

    // Determine which fields changed
    var changedFields = getChangedFields(headers, rowValues, lessonID);

    // Update stored checksum
    storeChecksum(lessonID, newChecksum);

    // Build payload
    var payload = {
      lessonID: lessonID,
      changedFields: changedFields,
      editedBy: Session.getActiveUser().getEmail() || 'unknown',
      timestamp: new Date().toISOString(),
      newChecksum: newChecksum
    };

    Logger.log('onEdit: Sending edit notification for ' + lessonID + ': ' + JSON.stringify(payload));

    // Send to Agent 16
    sendToAgent16(payload);

  } catch (error) {
    Logger.log('onEdit ERROR: ' + error.toString());
    // Gracefully fail — do not throw, as that would block the user's edit
  }
}


// ─── Checksum helpers ─────────────────────────────────────────────────────────

/**
 * Computes an MD5 checksum of the given string.
 *
 * @param {string} input
 * @returns {string} Hex-encoded MD5 digest
 */
function computeChecksum(input) {
  var rawBytes = Utilities.computeDigest(
    Utilities.DigestAlgorithm.MD5,
    input,
    Utilities.Charset.UTF_8
  );
  return rawBytes.map(function(b) {
    return ('0' + (b & 0xFF).toString(16)).slice(-2);
  }).join('');
}


/**
 * Retrieves the stored checksum for a lesson_id from the Checksums tab.
 *
 * @param {string} lessonID
 * @returns {string} The stored checksum, or '' if not found
 */
function getStoredChecksum(lessonID) {
  var checksumSheet = getOrCreateChecksumsSheet();
  var data = checksumSheet.getDataRange().getValues();

  for (var i = 0; i < data.length; i++) {
    if (String(data[i][0]).trim() === lessonID) {
      return String(data[i][1]).trim();
    }
  }
  return '';
}


/**
 * Stores or updates the checksum for a lesson_id in the Checksums tab.
 *
 * @param {string} lessonID
 * @param {string} checksum
 */
function storeChecksum(lessonID, checksum) {
  var checksumSheet = getOrCreateChecksumsSheet();
  var data = checksumSheet.getDataRange().getValues();

  for (var i = 0; i < data.length; i++) {
    if (String(data[i][0]).trim() === lessonID) {
      checksumSheet.getRange(i + 1, 2).setValue(checksum);
      checksumSheet.getRange(i + 1, 3).setValue(new Date().toISOString());
      return;
    }
  }

  // Not found — append a new row
  var nextRow = checksumSheet.getLastRow() + 1;
  checksumSheet.getRange(nextRow, 1).setValue(lessonID);
  checksumSheet.getRange(nextRow, 2).setValue(checksum);
  checksumSheet.getRange(nextRow, 3).setValue(new Date().toISOString());
}


/**
 * Returns the Checksums sheet, creating it if it doesn't exist.
 *
 * @returns {GoogleAppsScript.Spreadsheet.Sheet}
 */
function getOrCreateChecksumsSheet() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(CHECKSUMS_TAB_NAME);

  if (!sheet) {
    sheet = ss.insertSheet(CHECKSUMS_TAB_NAME);
    sheet.getRange(1, 1, 1, 3).setValues([['lesson_id', 'checksum', 'updated_at']]);
    sheet.setFrozenRows(1);
    Logger.log('Created Checksums sheet');
  }

  return sheet;
}


// ─── Field change detection ───────────────────────────────────────────────────

/**
 * Determines which named fields changed by comparing current row values
 * against previously stored values (if available).
 * Falls back to returning all non-empty header names if no prior state.
 *
 * @param {Array} headers - Row 1 header values
 * @param {Array} rowValues - Current row values
 * @param {string} lessonID
 * @returns {string[]} Array of field names that changed
 */
function getChangedFields(headers, rowValues, lessonID) {
  var changed = [];

  // Simple implementation: return all non-empty fields in the row
  // A more sophisticated version would compare against the last stored row snapshot.
  // For now we report headers where the value is non-empty.
  for (var i = 0; i < headers.length; i++) {
    var header = String(headers[i]).trim();
    if (header && header !== 'lesson_id') {
      // We could compare against stored snapshot here — for now flag all non-empty
      if (rowValues[i] !== '' && rowValues[i] !== null && rowValues[i] !== undefined) {
        changed.push(header);
      }
    }
  }

  return changed.length > 0 ? changed : ['(unknown fields)'];
}


// ─── Webhook delivery ─────────────────────────────────────────────────────────

/**
 * Sends the edit payload to the Agent 16 webhook.
 *
 * @param {Object} payload
 */
function sendToAgent16(payload) {
  var scriptProps = PropertiesService.getScriptProperties();
  var webhookUrl = scriptProps.getProperty('AGENT_16_WEBHOOK_URL');

  if (!webhookUrl) {
    Logger.log('ERROR: AGENT_16_WEBHOOK_URL script property is not set. ' +
      'Go to File > Project Properties > Script Properties and add it.');
    return;
  }

  var options = {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  };

  try {
    var response = UrlFetchApp.fetch(webhookUrl, options);
    var statusCode = response.getResponseCode();
    var responseText = response.getContentText();

    if (statusCode >= 200 && statusCode < 300) {
      Logger.log('Agent 16 notified successfully. Status: ' + statusCode);
    } else {
      Logger.log('Agent 16 returned non-2xx status: ' + statusCode + ' — ' + responseText);
    }
  } catch (fetchError) {
    Logger.log('Failed to reach Agent 16 webhook: ' + fetchError.toString());
    // Graceful failure — the edit is not blocked
  }
}


// ─── Setup and test functions ─────────────────────────────────────────────────

/**
 * Run this function ONCE to install the onEdit trigger.
 * Required before the automatic edit detection will work.
 *
 * How to run: In the Apps Script editor, select setupTriggers from the
 * function dropdown and click Run.
 */
function setupTriggers() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();

  // Remove any existing onEdit triggers to avoid duplicates
  var existingTriggers = ScriptApp.getProjectTriggers();
  for (var i = 0; i < existingTriggers.length; i++) {
    if (existingTriggers[i].getHandlerFunction() === 'onEdit') {
      ScriptApp.deleteTrigger(existingTriggers[i]);
      Logger.log('Removed existing onEdit trigger');
    }
  }

  // Install a fresh installable onEdit trigger
  ScriptApp.newTrigger('onEdit')
    .forSpreadsheet(ss)
    .onEdit()
    .create();

  Logger.log('onEdit trigger installed successfully for spreadsheet: ' + ss.getName());
  SpreadsheetApp.getUi().alert(
    '✅ Trigger installed!\n\n' +
    'The Lesson Edit Detector is now active.\n\n' +
    'Run testWebhook() to verify connectivity to Agent 16.'
  );
}


/**
 * Test connectivity to the Agent 16 webhook.
 * Run this from the Apps Script toolbar after setup to verify everything works.
 */
function testWebhook() {
  var scriptProps = PropertiesService.getScriptProperties();
  var webhookUrl = scriptProps.getProperty('AGENT_16_WEBHOOK_URL');

  if (!webhookUrl) {
    SpreadsheetApp.getUi().alert(
      '❌ AGENT_16_WEBHOOK_URL is not set!\n\n' +
      'Go to: File > Project Properties > Script Properties\n' +
      'Add key: AGENT_16_WEBHOOK_URL\n' +
      'Value: https://your-domain.com/webhook/lesson-edit-detect'
    );
    return;
  }

  var testPayload = {
    lessonID: 'TEST-W01-L01',
    changedFields: ['hook', 'core_content'],
    editedBy: Session.getActiveUser().getEmail() || 'test@example.com',
    timestamp: new Date().toISOString(),
    newChecksum: 'test_checksum_12345',
    _test: true
  };

  Logger.log('Sending test payload to: ' + webhookUrl);
  Logger.log('Payload: ' + JSON.stringify(testPayload));

  var options = {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(testPayload),
    muteHttpExceptions: true
  };

  try {
    var response = UrlFetchApp.fetch(webhookUrl, options);
    var statusCode = response.getResponseCode();
    var responseText = response.getContentText();

    Logger.log('Response status: ' + statusCode);
    Logger.log('Response body: ' + responseText);

    if (statusCode >= 200 && statusCode < 300) {
      SpreadsheetApp.getUi().alert(
        '✅ Webhook test successful!\n\n' +
        'URL: ' + webhookUrl + '\n' +
        'Status: ' + statusCode + '\n' +
        'Response: ' + responseText
      );
    } else {
      SpreadsheetApp.getUi().alert(
        '⚠️ Webhook returned non-2xx status.\n\n' +
        'URL: ' + webhookUrl + '\n' +
        'Status: ' + statusCode + '\n' +
        'Response: ' + responseText + '\n\n' +
        'This may be normal if the n8n workflow is not yet active.'
      );
    }
  } catch (error) {
    SpreadsheetApp.getUi().alert(
      '❌ Webhook connection failed!\n\n' +
      'URL: ' + webhookUrl + '\n' +
      'Error: ' + error.toString() + '\n\n' +
      'Check that your LMS domain is reachable from the internet.'
    );
    Logger.log('testWebhook ERROR: ' + error.toString());
  }
}
