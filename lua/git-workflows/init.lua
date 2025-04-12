local M = {}

local pending_workflows = {}
local total_pending = 0

local config = {
  refresh_seconds = 60,
  use_current = true,
  repos = {},
  statuses = { "pending", "waiting" },
  icon = "",
  severity_limits = {
    low = 0,
    med = 2,
    high = 4,
  },
  colors = {
    bg = {
      none = "#00820d",
      low = "#e8eb42",
      med = "#db8412",
      high = "#b8361c",
    },
    fg = {
      none = "#dddddd",
      low = "#222222",
      med = "#222222",
      high = "#dddddd",
    },
  },
}

function M.get_pending_count()
  return total_pending
end

function M.get_pending_text()
  return config.icon .. " " .. get_pending_count()
end

function M.get_colors()
  local severity = "none"
  if total_pending > config.severity_limits.high then
    severity = "high"
  elseif total_pending > config.severity_limits.med then
    severity = "med"
  elseif total_pending > config.severity_limits.low then
    severity = "low"
  end
  return {
    fg = config.colors.fg[severity],
    bg = config.colors.bg[severity],
    gui = "bold",
  }
end

function M.get_lualine_section()
  return {
    get_pending_text,
    color = get_colors,
    on_click = function()
      print("You Clicked it")
    end,
  }
end

function get_github_token()
  local github_token = os.getenv("GITHUB_TOKEN")
  if github_token == nil then
    github_token = os.getenv("GH_TOKEN")
  end
  if github_token == nil then
    error("GITHUB_TOKEN or GH_TOKEN must be set for git-workflows.nvim")
  end
  return github_token
end

function get_headers(github_token)
  return {
    "Content-Type: application/vnd.github.v3+json",
    "Authorization Bearer: " .. github_token,
    "X-GitHub-Api-Version: 2022-11-28",
  }
end

function get_git_base_url(repo)
  return "https://api.github.com/repos/" .. repo
end

function get_current_repo()
  local handle = io.popen("git remote get-url origin 2> /dev/null")
  if not handle then
    return nil
  end

  local url = handle:read("*a")
  handle:close()

  if not url or url == "" then
    return nil
  end
  url = vim.trim(url)

  -- Match SSH and HTTPS GitHub URLs
  local owner_repo = url:match("github.com[:/](.-)%.git$")
  return owner_repo
end

function update_pending_for_repo(repo, workflows)
  pending_workflows[repo] = repo_pending_workflows
  local total = 0
  for _, workflows in ipairs(pending_workflows) do
    total = total + #workflows
  end
  total_pending = total
end

function update_workflows_for_repo(github_token, repo)
  local url = get_git_base_url(repo) .. "/actions/runs?per_page=100"
  local headers = get_headers(github_token)
  local command = "curl -s "
  for _, header in ipairs(headers) do
    command = command .. '-H "' .. header .. '" '
  end
  command = command .. '-X GET "' .. url .. '"'

  vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        local rawdata = table.concat(data, "\n")
        local jsondata = vim.json.decode(rawdata)
        local repo_pending_workflows = {}

        for _, run in ipairs(jsondata.workflow_runs) do
          local match = false
          for _, desired_status in ipairs(config.statuses) do
            if desired_status == run.status then
              match = true
              break
            end
          end

          if match then
            table.insert(repo_pending_workflows, run)
          end
        end

        update_pending_for_repo(repo, repo_pending_workflows)
      end
    end,
  })
end

function update_pending_workflows(config, github_token)
  for _, repo in ipairs(config.repos) do
    update_workflows_for_repo(github_token, repo)
  end
end

function set_pending_workflow_timer(config, github_token)
  local timer = vim.uv.new_timer()
  timer:start(
    0,
    refresh_seconds * 1000,
    vim.schedule_wrap(function()
      update_pending_workflows(config, github_token)
    end)
  )
end

function M.setup(user_config)
  config = vim.tbl_deep_extend("force", config, user_config or {})
  local github_token = get_github_token()

  set_pending_workflow_timer(config, github_token)
end

return M
