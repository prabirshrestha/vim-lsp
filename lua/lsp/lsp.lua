local M = {}
local utils = require('lsp/utils')

function M.get_allowed_servers(buffer_filetype, servers)
  local active_servers = utils.list()

  for server_name, server_config in utils.dict_wrapper(servers)() do
    local blocked = false
    local server_info = server_config['server_info']
    local blocklist = server_info['blocklist'] or server_info['blacklist']
    local allowlist = server_info['allowlist'] or server_info['whitelist']
    if blocklist then
      for filetype in list_wrapper(blocklist)() do
        if filetype:upper() == buffer_filetype:upper() or filetype == '*' then
          blocked = true
          break
        end
      end
    end

    if blocked then
      goto continue
    end

    if allowlist then
      for filetype in utils.list_wrapper(allowlist)() do
        if filetype:upper() == buffer_filetype:upper() or filetype == '*' then
          table.insert(active_servers, server_name)
          break
        end
      end
    end

    ::continue::
  end

  return active_servers
end

return M
