vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.scrolloff = 8
vim.opt.wrap = false
vim.opt.virtualedit = "onemore"
vim.opt.clipboard = "unnamedplus"

vim.opt.expandtab = true
vim.opt.shiftwidth = 4
vim.opt.tabstop = 4
vim.opt.softtabstop = 4

if vim.g.vscode then
  local vscode = require("vscode")
  local map = vim.keymap.set

  map("n", "<leader>e", function() vscode.action("workbench.view.explorer") end, { desc = "Toggle explorer" })
  map("n", "<leader>o", function() vscode.action("workbench.view.explorer") end, { desc = "Focus explorer" })
  map("n", "<leader>f", function() vscode.action("workbench.action.quickOpen") end, { desc = "Quick open file" })
  map("n", "<leader>F", function() vscode.action("workbench.files.action.showActiveFileInExplorer") end, { desc = "Reveal current file" })
  map("n", "<leader>x", function() vscode.action("workbench.action.closeActiveEditor") end, { desc = "Close editor" })

  map("n", "<leader>n", function() vscode.action("editor.action.rename") end, { desc = "Rename symbol" })
  map({ "n", "v" }, "<leader>ca", function() vscode.action("editor.action.quickFix") end, { desc = "Code action" })

  map("n", "gd", function() vscode.action("editor.action.revealDefinition") end)
  map("n", "gr", function() vscode.action("editor.action.goToReferences") end)
  map("n", "gi", function() vscode.action("editor.action.goToImplementation") end)
  map("n", "K", function() vscode.action("editor.action.showHover") end)
  map("n", "[d", function() vscode.action("editor.action.marker.prev") end)
  map("n", "]d", function() vscode.action("editor.action.marker.next") end)

end
