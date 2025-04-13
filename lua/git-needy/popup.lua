local popup = require("plenary.popup")

local M = {}

local function open_url(url)
  local open_cmd
  if vim.fn.has("mac") == 1 then
    open_cmd = { "open", url }
  elseif vim.fn.has("unix") == 1 then
    open_cmd = { "xdg-open", url }
  elseif vim.fn.has("win32") == 1 then
    open_cmd = { "cmd.exe", "/C", "start", url }
  else
    vim.notify("Unsupported OS for opening URLs", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart(open_cmd, { detach = true })
end

local function create_buffer(pending_workflows)
  local width = 60 -- config.width or 60
  local height = 20 -- config.height or 10
  local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>bd!<CR>", { noremap = true, silent = true })

  -- vim.api.nvim_buf_set_text(bufnr, row - 1, col, row - 1, col, { "TEXT" })

  local Needy_win_id, win = popup.create(bufnr, {
    title = "GitWorkflows",
    highlight = "GitWorkflows",
    line = math.floor(((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    minwidth = width,
    minheight = height,
    borderchars = borderchars,
  })
  return bufnr
end

local ns_id = vim.api.nvim_create_namespace("git-needy-ns")

local function highlight_current_line(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1) -- clear previous highlights
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- get current line (0-based)
  vim.api.nvim_buf_add_highlight(bufnr, ns_id, "Visual", line, 0, -1)
end

function M.open_popup_window(pending_workflows)
  local bufnr = create_buffer(pending_workflows)
  highlight_current_line(bufnr)

  local line_space = "  "

  local tree_not_last = line_space .. "├─ "
  local tree_last = line_space .. "└─ "

  local workflow_lines = {}

  local lines = {}
  local cur_line = 1
  for repo, workflows in pairs(pending_workflows) do
    print(workflows)
    local count = #workflows
    if count > 0 then
      table.insert(lines, line_space .. " " .. repo)
    end
    for i, workflow in ipairs(workflows) do
      local title = workflow.display_title
      workflow_lines[cur_line] = workflow
      cur_line = cur_line + 1
      if i == count then
        table.insert(lines, tree_last .. title)
      else
        table.insert(lines, tree_not_last .. title)
      end
    end
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, #lines, false, lines)

  -- Only allow normal mode
  vim.api.nvim_create_autocmd("ModeChanged", {
    buffer = bufnr,
    callback = function()
      local mode = vim.api.nvim_get_mode().mode
      if mode ~= "n" then
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
      end
    end,
    desc = "Force back to normal mode",
  })

  -- Highlight current line
  vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, {
    buffer = bufnr,
    callback = function()
      highlight_current_line(bufnr)
    end,
    desc = "Highlight current line",
  })

  function get_current_workflow()
    local line = vim.api.nvim_win_get_cursor(0)[1] - 1 -- get current line (0-based)
    return workflow_lines[line]
  end

  function open_workflow_url()
    local wf = get_current_workflow()
    local url = wf.html_url
    open_url(url)
    vim.api.nvim_command("bd!")
  end

  vim.keymap.set("n", "<CR>", open_workflow_url, { buffer = bufnr, desc = "Open Workflow URL" })
end

return M
