export function createDownloadButton(inputs, fileName) {
  const button = document.createElement("button");
  button.className = "btn btn-primary";
  button.type = "button";
  button.textContent = "Download Your Notes";
  button.onclick = () => downloadNotes(inputs, fileName);
  return button;
}

export function downloadNotes(inputs, fileName) {
  const combinedText = combineInputValues(inputs);

  if (!combinedText.replace(/[\s—-]+/g, "").length) {
    alert("You haven't written any notes yet. Fill in at least one field before downloading.");
    return;
  }

  const blob = createTextBlob(combinedText);
  const url = URL.createObjectURL(blob);

  triggerDownload(url, fileName);
  cleanupUrl(url);
}

function combineInputValues(inputs) {
  return inputs
    .map(input => input?.value?.toString() || "")
    .join("\n\n---\n\n");
}

function createTextBlob(content) {
  return new Blob([content], { type: "text/plain" });
}

function triggerDownload(url, fileName) {
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  link.click();
}

function cleanupUrl(url) {
  setTimeout(() => URL.revokeObjectURL(url), 100);
}