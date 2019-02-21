# vim-lsp

Async [Language Server Protocol](https://github.com/Microsoft/language-server-protocol) plugin for vim8 and neovim.

# Installing

```viml
Plug 'prabirshrestha/async.vim'
Plug 'prabirshrestha/vim-lsp'
```

_Note: [async.vim](https://github.com/prabirshrestha/async.vim) is required and is used to normalize jobs between vim8 and neovim._

## Registering servers

**For other languages please refer to the [wiki](https://github.com/prabirshrestha/vim-lsp/wiki/Servers).**

```viml
if executable('pyls')
    " pip install python-language-server
    au User lsp_setup call lsp#register_server({
        \ 'name': 'pyls',
        \ 'cmd': {server_info->['pyls']},
        \ 'whitelist': ['python'],
        \ })
endif
```

While most of the time it is ok to just set the `name`, `cmd` and `whitelist` there are times when you need to get more control of the `root_uri`. By default `root_uri` for the buffer can be found using `lsp#utils#get_default_root_uri()` which internaly uses `getcwd()`. Here is an example that sets the `root_uri` to the directory where it contains `tsconfig.json` and traverses up the directories automatically, if it isn't found it returns empty string which tells `vim-lsp` to start the server but don't initialize the server. If you would like to avoid starting the server you can return empty array for `cmd`.

```vim
if executable('typescript-language-server')
    au User lsp_setup call lsp#register_server({
        \ 'name': 'typescript-language-server',
        \ 'cmd': {server_info->[&shell, &shellcmdflag, 'typescript-language-server --stdio']},
        \ 'root_uri':{server_info->lsp#utils#path_to_uri(lsp#utils#find_nearest_parent_file_directory(lsp#utils#get_buffer_path(), 'tsconfig.json'))},
        \ 'whitelist': ['typescript'],
        \ })
endif
```

vim-lsp supports incremental changes of Language Server Protocol.

## auto-complete

Refer to docs on configuring omnifunc or [asyncomplete.vim](https://github.com/prabirshrestha/asyncomplete.vim).

## Supported commands

**Note:**
* Some servers may only support partial commands.
* While it is possible to register multiple servers for the same filetype, some commands will pick only the first server that supports it. For example, it doesn't make sense for rename and format commands to be sent to multiple servers.

| Command | Description|
|--|--|
|`:LspCodeAction`| Gets a list of possible commands that can be applied to a file so it can be fixed (quick fix) |
|`:LspDeclaration`| Go to declaration |
|`:LspDefinition`| Go to definition |
|`:LspDocumentDiagnostics`| Get current document diagnostics information |
|`:LspDocumentFormat`| Format entire document |
|`:LspDocumentRangeFormat`| Format document selection |
|`:LspDocumentSymbol`| Show document symbols |
|`:LspHover`| Show hover information |
|`:LspImplementation` | Show implementation of interface |
|`:LspNextError`| jump to next error |
|`:LspPreviousError`| jump to previous error |
|`:LspReferences`| Find references |
|`:LspRename`| Rename symbol |
|`:LspStatus` | Show the status of the language server |
|`:LspTypeDefinition`| Go to type definition |
|`:LspWorkspaceSymbol`| Search/Show workspace symbol |

### Diagnostics

Document diagnostics (e.g. warnings, errors) are enabled by default, but if you
preferred to turn them off and use other plugins instead (like
[Neomake](https://github.com/neomake/neomake) or
[ALE](https://github.com/w0rp/ale), set `g:lsp_diagnostics_enabled` to
`0`:

```viml
let g:lsp_diagnostics_enabled = 0         " disable diagnostics support
```

#### Signs

```viml
let g:lsp_signs_enabled = 1         " enable signs
let g:lsp_diagnostics_echo_cursor = 1 " enable echo under cursor when in normal mode
```

Four groups of signs are defined and used: `LspError`, `LspWarning`, `LspInformation`, `LspHint`. It is possible to set custom text or icon that will be used for each sign (note that icons are only available in GUI). To do this, set some of the following globals: `g:lsp_signs_error`, `g:lsp_signs_warning`, `g:lsp_signs_information`, `g:lsp_signs_hint`. They should be set to a dict, that contains either text that will be used as sign in terminal, or icon that will be used for GUI, or both. For example:

```viml
let g:lsp_signs_error = {'text': '✗'}
let g:lsp_signs_warning = {'text': '‼', 'icon': '/path/to/some/icon'} " icons require GUI
let g:lsp_signs_hint = {'icon': '/path/to/some/other/icon'} " icons require GUI
```

Also two highlight groups for every sign group are defined (for example for LspError these are LspErrorText and LspErrorLine). By default, LspError text is highlighted using Error group, LspWarning is highlighted as Todo, others use Normal group. Line highlighting is not set by default. If your colorscheme of choise does not provide any of these, it is possible to clear them or link to some other group, like so:

```viml
highlight link LspErrorText GruvboxRedSign " requires gruvbox
highlight clear LspWarningLine
```

## Debugging

In order to enable file logging set `g:lsp_log_file`.

```vim
let g:lsp_log_verbose = 1
let g:lsp_log_file = expand('~/vim-lsp.log')

" for asyncomplete.vim log
let g:asyncomplete_log_file = expand('~/asyncomplete.log')
```
