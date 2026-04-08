/**
 * OkiSignal - Google Apps Script Webhook
 *
 * Deploy: Extensions > Apps Script > Deploy as Web App
 * Settings: Execute as "Me", Access "Anyone"
 *
 * Required Sheets:
 * - "Signals" — trade entries/exits log
 * - "WeeklyReports" — weekly summary
 */

function doPost(e) {
  try {
    var data = JSON.parse(e.postData.contents);
    var sheet = SpreadsheetApp.getActiveSpreadsheet();

    if (data.action === "new_signal") {
      return handleNewSignal(sheet, data);
    }

    if (data.action === "close_signal") {
      return handleCloseSignal(sheet, data);
    }

    if (data.action === "weekly_report") {
      return handleWeeklyReport(sheet, data);
    }

    return jsonResponse({ status: "error", message: "Unknown action" });
  } catch (err) {
    return jsonResponse({ status: "error", message: err.toString() });
  }
}

function handleNewSignal(sheet, data) {
  var ws = getOrCreateSheet(sheet, "Signals", [
    "DateTime", "Ticket", "Magic", "Strategy", "Symbol",
    "Direction", "Entry", "SL", "TP1", "TP2", "Volume",
    "ClosePrice", "Profit", "ProfitPips", "CloseReason", "Duration"
  ]);

  ws.appendRow([
    data.timestamp,
    data.ticket,
    data.magic,
    data.strategy,
    data.symbol,
    data.direction,
    data.entry,
    data.sl,
    data.tp1,
    data.tp2 || "",
    data.volume,
    "", "", "", "", ""
  ]);

  return jsonResponse({ status: "ok", action: "new_signal" });
}

function handleCloseSignal(sheet, data) {
  var ws = sheet.getSheetByName("Signals");
  if (!ws) return jsonResponse({ status: "error", message: "Signals sheet not found" });

  var dataRange = ws.getDataRange().getValues();

  for (var i = dataRange.length - 1; i >= 1; i--) {
    if (String(dataRange[i][1]) === String(data.ticket)) {
      var row = i + 1;
      ws.getRange(row, 12).setValue(data.closePrice);
      ws.getRange(row, 13).setValue(data.profit);
      ws.getRange(row, 14).setValue(data.profitPips);
      ws.getRange(row, 15).setValue(data.closeReason);
      ws.getRange(row, 16).setValue(data.duration);
      return jsonResponse({ status: "ok", action: "close_signal", row: row });
    }
  }

  return jsonResponse({ status: "not_found", ticket: data.ticket });
}

function handleWeeklyReport(sheet, data) {
  var ws = getOrCreateSheet(sheet, "WeeklyReports", [
    "WeekEnding", "TotalTrades", "WinRate", "TotalPips",
    "ProfitFactor", "BestStrategy", "WorstStrategy"
  ]);

  ws.appendRow([
    data.weekEnding,
    data.totalTrades,
    data.winRate,
    data.totalPips,
    data.profitFactor,
    data.bestStrategy,
    data.worstStrategy
  ]);

  return jsonResponse({ status: "ok", action: "weekly_report" });
}

function getOrCreateSheet(spreadsheet, name, headers) {
  var ws = spreadsheet.getSheetByName(name);
  if (!ws) {
    ws = spreadsheet.insertSheet(name);
    ws.appendRow(headers);
    ws.getRange(1, 1, 1, headers.length).setFontWeight("bold");
  }
  return ws;
}

function jsonResponse(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
