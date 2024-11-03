export function downloadNotes(inputs, fileName) {
  // Combine values from all inputs
  const combinedText = inputs.map(input => {
    // Convert each input's value to a string and handle undefined/null gracefully
    return (input !== undefined && input !== null) ? String(input.value) : "";
  }).join("\n\n---\n\n"); // Optional separator for readability

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