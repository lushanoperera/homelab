// State
let data = null;
let selectedIds = new Set();
let lastClickedIndex = null;

// Type mapping
const TYPE_NAMES = {
  1: "Login",
  2: "Note",
  3: "Card",
  4: "Identity",
};

const TYPE_CLASSES = {
  1: "login",
  2: "note",
  3: "card",
  4: "identity",
};

// DOM Elements
const fileInput = document.getElementById("fileInput");
const fileName = document.getElementById("fileName");
const searchInput = document.getElementById("searchInput");
const folderFilter = document.getElementById("folderFilter");
const typeFilter = document.getElementById("typeFilter");
const itemsBody = document.getElementById("itemsBody");
const headerCheckbox = document.getElementById("headerCheckbox");
const selectAllBtn = document.getElementById("selectAllBtn");
const deselectAllBtn = document.getElementById("deselectAllBtn");
const deleteSelectedBtn = document.getElementById("deleteSelectedBtn");
const moveFolderSelect = document.getElementById("moveFolderSelect");
const moveSelectedBtn = document.getElementById("moveSelectedBtn");
const exportBtn = document.getElementById("exportBtn");
const stats = document.getElementById("stats");
const editModal = document.getElementById("editModal");
const editItemId = document.getElementById("editItemId");
const editName = document.getElementById("editName");
const editFolder = document.getElementById("editFolder");
const cancelEditBtn = document.getElementById("cancelEditBtn");
const saveEditBtn = document.getElementById("saveEditBtn");
const toast = document.getElementById("toast");

// Event Listeners
fileInput.addEventListener("change", loadFile);
searchInput.addEventListener("input", debounce(renderItems, 300));
folderFilter.addEventListener("change", renderItems);
typeFilter.addEventListener("change", renderItems);
headerCheckbox.addEventListener("change", toggleAllVisible);
selectAllBtn.addEventListener("click", selectAll);
deselectAllBtn.addEventListener("click", deselectAll);
deleteSelectedBtn.addEventListener("click", deleteSelected);
moveSelectedBtn.addEventListener("click", moveSelected);
exportBtn.addEventListener("click", exportData);
cancelEditBtn.addEventListener("click", closeModal);
saveEditBtn.addEventListener("click", saveEdit);

// Close modal on outside click
editModal.addEventListener("click", (e) => {
  if (e.target === editModal) closeModal();
});

// Keyboard shortcuts
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closeModal();
  if (
    e.key === "Delete" &&
    selectedIds.size > 0 &&
    document.activeElement.tagName !== "INPUT"
  ) {
    deleteSelected();
  }
});

// Load JSON file
function loadFile(e) {
  const file = e.target.files[0];
  if (!file) return;

  fileName.textContent = file.name;

  const reader = new FileReader();
  reader.onload = (event) => {
    try {
      data = JSON.parse(event.target.result);
      if (!data.items || !Array.isArray(data.items)) {
        throw new Error("Invalid Bitwarden export format");
      }
      enableControls();
      populateFolderFilters();
      renderItems();
      showToast(`Loaded ${data.items.length} items`, "success");
    } catch (err) {
      showToast(`Error: ${err.message}`, "error");
      data = null;
    }
  };
  reader.readAsText(file);
}

// Enable controls after file load
function enableControls() {
  searchInput.disabled = false;
  folderFilter.disabled = false;
  typeFilter.disabled = false;
  headerCheckbox.disabled = false;
  selectAllBtn.disabled = false;
  deselectAllBtn.disabled = false;
  deleteSelectedBtn.disabled = false;
  moveFolderSelect.disabled = false;
  moveSelectedBtn.disabled = false;
  exportBtn.disabled = false;
}

// Populate folder dropdowns
function populateFolderFilters() {
  const folders = data.folders || [];

  // Clear existing options except first
  folderFilter.innerHTML = '<option value="">All Folders</option>';
  folderFilter.innerHTML += '<option value="__none__">No Folder</option>';
  moveFolderSelect.innerHTML = '<option value="">Move to Folder...</option>';
  moveFolderSelect.innerHTML += '<option value="__none__">No Folder</option>';
  editFolder.innerHTML = '<option value="">No Folder</option>';

  folders.forEach((folder) => {
    const option1 = document.createElement("option");
    option1.value = folder.id;
    option1.textContent = folder.name;
    folderFilter.appendChild(option1);

    const option2 = document.createElement("option");
    option2.value = folder.id;
    option2.textContent = folder.name;
    moveFolderSelect.appendChild(option2);

    const option3 = document.createElement("option");
    option3.value = folder.id;
    option3.textContent = folder.name;
    editFolder.appendChild(option3);
  });
}

// Get folder name by ID
function getFolderName(folderId) {
  if (!folderId || !data.folders) return "-";
  const folder = data.folders.find((f) => f.id === folderId);
  return folder ? folder.name : "-";
}

// Get primary URL from item
function getPrimaryUrl(item) {
  if (item.login && item.login.uris && item.login.uris.length > 0) {
    const uri = item.login.uris[0].uri || "";
    try {
      const url = new URL(uri);
      return url.hostname;
    } catch {
      return uri.substring(0, 30);
    }
  }
  return "-";
}

// Get username from item
function getUsername(item) {
  if (item.login && item.login.username) {
    return item.login.username;
  }
  return "-";
}

// Filter items based on search and filters
function getFilteredItems() {
  if (!data || !data.items) return [];

  const search = searchInput.value.toLowerCase().trim();
  const folderId = folderFilter.value;
  const typeId = typeFilter.value;

  return data.items.filter((item) => {
    // Folder filter
    if (folderId === "__none__" && item.folderId) return false;
    if (folderId && folderId !== "__none__" && item.folderId !== folderId)
      return false;

    // Type filter
    if (typeId && item.type !== parseInt(typeId)) return false;

    // Search filter
    if (search) {
      const name = (item.name || "").toLowerCase();
      const username = getUsername(item).toLowerCase();
      const url = getPrimaryUrl(item).toLowerCase();
      if (
        !name.includes(search) &&
        !username.includes(search) &&
        !url.includes(search)
      ) {
        return false;
      }
    }

    return true;
  });
}

// Render items table
function renderItems() {
  if (!data) return;

  const filtered = getFilteredItems();
  itemsBody.innerHTML = "";

  if (filtered.length === 0) {
    itemsBody.innerHTML =
      '<tr class="empty-state"><td colspan="7">No items match your filters</td></tr>';
    updateStats();
    return;
  }

  filtered.forEach((item, index) => {
    const row = document.createElement("tr");
    const isSelected = selectedIds.has(item.id);
    if (isSelected) row.classList.add("selected");

    row.innerHTML = `
            <td class="checkbox-col">
                <input type="checkbox" data-id="${item.id}" data-index="${index}" ${isSelected ? "checked" : ""}>
            </td>
            <td class="item-name">${escapeHtml(item.name || "Unnamed")}</td>
            <td>${escapeHtml(getUsername(item))}</td>
            <td class="item-url" title="${escapeHtml(getPrimaryUrl(item))}">${escapeHtml(getPrimaryUrl(item))}</td>
            <td><span class="item-type ${TYPE_CLASSES[item.type] || ""}">${TYPE_NAMES[item.type] || "Unknown"}</span></td>
            <td class="item-folder">${escapeHtml(getFolderName(item.folderId))}</td>
            <td class="actions-cell">
                <button class="btn btn-icon" onclick="openEditModal('${item.id}')" title="Edit">✏️</button>
                <button class="btn btn-icon" onclick="deleteItem('${item.id}')" title="Delete">🗑️</button>
            </td>
        `;

    // Checkbox click handler with shift-click support
    const checkbox = row.querySelector('input[type="checkbox"]');
    checkbox.addEventListener("click", (e) =>
      handleCheckboxClick(e, item.id, index),
    );

    itemsBody.appendChild(row);
  });

  updateStats();
  updateHeaderCheckbox();
}

// Handle checkbox click with shift-click range selection
function handleCheckboxClick(e, itemId, index) {
  if (e.shiftKey && lastClickedIndex !== null) {
    const filtered = getFilteredItems();
    const start = Math.min(lastClickedIndex, index);
    const end = Math.max(lastClickedIndex, index);

    for (let i = start; i <= end; i++) {
      selectedIds.add(filtered[i].id);
    }
    renderItems();
  } else {
    toggleSelect(itemId);
  }
  lastClickedIndex = index;
}

// Toggle item selection
function toggleSelect(itemId) {
  if (selectedIds.has(itemId)) {
    selectedIds.delete(itemId);
  } else {
    selectedIds.add(itemId);
  }
  renderItems();
}

// Toggle all visible items
function toggleAllVisible() {
  const filtered = getFilteredItems();
  const allSelected = filtered.every((item) => selectedIds.has(item.id));

  if (allSelected) {
    filtered.forEach((item) => selectedIds.delete(item.id));
  } else {
    filtered.forEach((item) => selectedIds.add(item.id));
  }
  renderItems();
}

// Select all visible items
function selectAll() {
  const filtered = getFilteredItems();
  filtered.forEach((item) => selectedIds.add(item.id));
  renderItems();
}

// Deselect all items
function deselectAll() {
  selectedIds.clear();
  renderItems();
}

// Update header checkbox state
function updateHeaderCheckbox() {
  const filtered = getFilteredItems();
  if (filtered.length === 0) {
    headerCheckbox.checked = false;
    headerCheckbox.indeterminate = false;
    return;
  }

  const selectedCount = filtered.filter((item) =>
    selectedIds.has(item.id),
  ).length;
  headerCheckbox.checked = selectedCount === filtered.length;
  headerCheckbox.indeterminate =
    selectedCount > 0 && selectedCount < filtered.length;
}

// Update statistics
function updateStats() {
  const total = data ? data.items.length : 0;
  const selected = selectedIds.size;
  const folders = data && data.folders ? data.folders.length : 0;
  stats.textContent = `Items: ${total} | Selected: ${selected} | Folders: ${folders}`;
}

// Delete single item
function deleteItem(itemId) {
  if (!confirm("Delete this item?")) return;

  data.items = data.items.filter((item) => item.id !== itemId);
  selectedIds.delete(itemId);
  renderItems();
  showToast("Item deleted", "success");
}

// Delete selected items
function deleteSelected() {
  if (selectedIds.size === 0) {
    showToast("No items selected", "info");
    return;
  }

  if (!confirm(`Delete ${selectedIds.size} selected items?`)) return;

  data.items = data.items.filter((item) => !selectedIds.has(item.id));
  const count = selectedIds.size;
  selectedIds.clear();
  renderItems();
  showToast(`Deleted ${count} items`, "success");
}

// Move selected items to folder
function moveSelected() {
  const folderId = moveFolderSelect.value;
  if (!folderId) {
    showToast("Select a folder first", "info");
    return;
  }

  if (selectedIds.size === 0) {
    showToast("No items selected", "info");
    return;
  }

  const targetFolderId = folderId === "__none__" ? null : folderId;

  data.items.forEach((item) => {
    if (selectedIds.has(item.id)) {
      item.folderId = targetFolderId;
    }
  });

  const folderName = targetFolderId
    ? getFolderName(targetFolderId)
    : "No Folder";
  showToast(`Moved ${selectedIds.size} items to ${folderName}`, "success");
  renderItems();
}

// Open edit modal
function openEditModal(itemId) {
  const item = data.items.find((i) => i.id === itemId);
  if (!item) return;

  editItemId.value = itemId;
  editName.value = item.name || "";
  editFolder.value = item.folderId || "";
  editModal.classList.add("active");
  editName.focus();
}

// Close edit modal
function closeModal() {
  editModal.classList.remove("active");
}

// Save edit
function saveEdit() {
  const itemId = editItemId.value;
  const item = data.items.find((i) => i.id === itemId);
  if (!item) return;

  const newName = editName.value.trim();
  if (!newName) {
    showToast("Name cannot be empty", "error");
    return;
  }

  item.name = newName;
  item.folderId = editFolder.value || null;

  closeModal();
  renderItems();
  showToast("Item updated", "success");
}

// Export modified data
function exportData() {
  if (!data) return;

  const exportObj = {
    encrypted: data.encrypted || false,
    folders: data.folders || [],
    items: data.items,
  };

  const json = JSON.stringify(exportObj, null, 2);
  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);

  const a = document.createElement("a");
  a.href = url;
  a.download = `bitwarden_export_modified_${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);

  showToast("Export downloaded", "success");
}

// Show toast notification
function showToast(message, type = "info") {
  toast.textContent = message;
  toast.className = `toast ${type} show`;

  setTimeout(() => {
    toast.classList.remove("show");
  }, 3000);
}

// Escape HTML to prevent XSS
function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

// Debounce utility
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

// Make functions globally available for inline onclick handlers
window.openEditModal = openEditModal;
window.deleteItem = deleteItem;
