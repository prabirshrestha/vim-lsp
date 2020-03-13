"
" NOTE: Currently vim-lsp's workspace feature is
"
" - configuration stores per server.
" - folders stores per server.
" - support one only workspace
"
"

"
" {
"   [server_name]: {
"     'config': { ..., },
"     'folders': [...]
"   }
" }
"
let s:workspace = {}

"
" lsp#ui#vim#workspace#_ensure_workspace
"
function! lsp#ui#vim#workspace#_ensure_workspace(server_name) abort
  if !lsp#capabilities#has_workspace_folders_supported(a:server_name)
    return
  endif

  let l:server_info = lsp#get_server_info(a:server_name)
  if !has_key(l:server_info, 'root_uri')
    return
  endif

  let l:root_uri = l:server_info['root_uri'](l:server_info)
  if l:root_uri ==# ''
    return
  endif

  " Initialize workspace (this may sent `workspace/didChangeConfiguration`)
  let l:workspace = s:init_workspace(a:server_name)

  " find already registered folder.
  let l:folder = v:null
  for l:folder in l:workspace['folders']
    if l:folder.uri ==# l:root_uri
      break
    endif
    let l:folder = v:null
  endfor
  if !empty(l:folder)
    return
  endif

  " add new folder.
  let l:folder = {
  \   'name': printf('[LSP] automatic workspace folder: %s', l:root_uri),
  \   'uri': l:root_uri
  \ }
  call add(l:workspace['folders'], l:folder)

  call lsp#send_request(a:server_name, {
  \   'method': 'workspace/didChangeWorkspaceFolders',
  \   'params': {
  \     'event': {
  \       'added': [l:folder],
  \       'removed': []
  \     }
  \   }
  \ })
endfunction

"
" lsp#ui#vim#workspace#_update_workspace_config
"
function! lsp#ui#vim#workspace#_update_workspace_config(server_name, config) abort
  let l:workspace = s:init_workspace(a:server_name)
  call lsp#utils#merge_dict(l:workspace['config'], a:config)
  call lsp#send_request(a:server_name, {
  \   'method': 'workspace/didChangeConfiguration',
  \   'params': {
  \     'settings': l:workspace['config']
  \   }
  \ })
endfunction

"
" init_workspace
"
function! s:init_workspace(server_name) abort
  " If does not initialized workspace for the server, initialize and send configuration.
  if !has_key(s:workspace, a:server_name)
    let s:workspace[a:server_name] = {
    \   'config': {},
    \   'folders': []
    \ }

    let l:server_info = lsp#get_server_info(a:server_name)
    if has_key(l:server_info, 'workspace_config')
      call lsp#ui#vim#workspace#_update_workspace_config(a:server_name, l:server_info['workspace_config'])
    endif
  endif
  return s:workspace[a:server_name]
endfunction

