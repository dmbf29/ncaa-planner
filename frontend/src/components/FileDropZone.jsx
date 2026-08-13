// Shared screenshot upload widget for the "Dynasty Update" AI-extraction pages:
// file picker + paste-from-clipboard, thumbnail previews, per-file remove.
function FileDropZone({ title, hint, files, onFilesChange }) {
  const handleFileInput = (e) => {
    onFilesChange([...files, ...Array.from(e.target.files || [])]);
    e.target.value = "";
  };

  const handlePaste = (e) => {
    const imageFiles = Array.from(e.clipboardData?.items || [])
      .filter((item) => item.kind === "file" && item.type.startsWith("image/"))
      .map((item) => item.getAsFile())
      .filter(Boolean);
    if (imageFiles.length === 0) return;
    e.preventDefault();
    onFilesChange([...files, ...imageFiles]);
  };

  const removeFile = (index) => onFilesChange(files.filter((_, i) => i !== index));

  return (
    <div
      className="space-y-2 rounded-md border border-border p-3 focus:outline-none focus-visible:ring-2 focus-visible:ring-burnt dark:border-darkborder"
      tabIndex={0}
      onPaste={handlePaste}
    >
      <div>
        <p className="text-sm font-semibold text-textPrimary dark:text-white">{title}</p>
        <p className="text-xs text-textSecondary">{hint}</p>
        <p className="text-xs text-textSecondary">Click here, then paste (⌘V / Ctrl+V) a copied screenshot.</p>
      </div>
      <input
        type="file"
        accept="image/*"
        multiple
        onChange={handleFileInput}
        className="block w-full text-xs text-textSecondary file:mr-3 file:rounded-md file:border-0 file:bg-burnt file:px-3 file:py-1.5 file:text-xs file:font-semibold file:text-white"
      />
      {files.length > 0 && (
        <div className="grid grid-cols-4 gap-2 sm:grid-cols-6">
          {files.map((file, index) => (
            <div key={`${file.name}-${index}`} className="relative">
              <img
                src={URL.createObjectURL(file)}
                alt={file.name}
                className="h-16 w-full rounded-md border border-border object-cover dark:border-darkborder"
              />
              <button
                type="button"
                onClick={() => removeFile(index)}
                className="absolute -right-1 -top-1 flex h-5 w-5 items-center justify-center rounded-full bg-danger text-xs text-white"
              >
                ✕
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default FileDropZone;
