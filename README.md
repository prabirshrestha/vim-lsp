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
        \ 'cmd': {server_info->[&shell, &shellcmdflag, 'typescript-language-server', '--stdio']},
        \ 'root_uri':{server_info->lsp#utils#path_to_uri(lsp#utils#find_nearest_parent_file_directory(lsp#utils#get_buffer_path(), 'tsconfig.json'))},
        \ 'whitelist': ['typescript'],
        \ })
endif
```

## auto-complete

`vim-lsp` by default only provides basic omnifunc support for autocomplete. Completion can be made asynchronous by setting `g:lsp_async_completion`. Note that this may cause unexpected behavior in some plugins such as MUcomplete.

If you would like to have more advanced features please use asyncomplete.vim as described below.

### omnifunc

```vim
" let g:lsp_async_completion = 1

autocmd FileType typescript setlocal omnifunc=lsp#complete
```

### asyncomplete.vim

[asyncomplete.vim](https://github.com/prabirshrestha/asyncomplete.vim) is a async auto complete plugin for vim8 and neovim written in pure vim script without any python dependencies.

```viml
Plug 'prabirshrestha/asyncomplete.vim'
Plug 'prabirshrestha/asyncomplete-lsp.vim'
```

## Supported commands

**Note:**
* Some servers may only support partial commands.
* While it is possible to register multiple servers for the same filetype, some commands will pick only pick the first server that supports it. For example, it doesn't make sense for rename and format commands to be sent to multiple servers.

| Command | Description|
|--|--|
|`:LspDocumentDiagnostics`| Get current document diagnostics information |
|`:LspDefinition`| Go to definition |
|`:LspDocumentFormat`| Format entire document |
|`:LspDocumentRangeFormat`| Format document selection |
|`:LspDocumentSymbol`| Show document symbols |
|`:LspHover`| Show hover information |
|`:LspReferences`| Find references |
|`:LspRename`| Rename symbol |
|`:LspWorkspaceSymbol`| Search/Show workspace symbol |

### Diagnostics

```
let g:lsp_signs_enabled = 1         " enable signs
let g:lsp_diagnostics_echo_cursor = 1 " enable echo under cursor when in normal mode
```

## Debugging

In order to enable file logging set `g:lsp_log_file`.

```vim
let g:lsp_log_verbose = 1
let g:lsp_log_file = expand('~/vim-lsp.log')

" for asyncomplete.vim log
let g:asyncomplete_log_file = expand('~/asyncomplete.log')
```
