export function downloadNotes(textAreas, fileName) {
  // Access values of the provided text areas and combine them
  const combinedText = textAreas.map(area => area.value).join("\n\n---\n\n");
  
  // Create a Blob and set up download
  const blob = new Blob([combinedText], { type: "text/plain" });
  const url = URL.createObjectURL(blob);
  
  // Create a temporary link to download the file
  const link = document.createElement("a");
  link.href = url;
  link.download = fileName;
  link.click();
  
  // Clean up the URL to release memory
  setTimeout(() => URL.revokeObjectURL(url), 100);
}