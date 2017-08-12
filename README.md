# vim-lsp

Async [Language Server Protocol](https://github.com/Microsoft/language-server-protocol) plugin for vim8 and neovim.
Internally vim-lsp uses [async.vim](https://github.com/prabirshrestha/async.vim).

# Installing

```viml
Plug 'prabirshrestha/async.vim'
Plug 'prabirshrestha/vim-lsp'
```

_Note: [async.vim](https://github.com/prabirshrestha/async.vim) is required to normalize jobs between vim8 and neovim._

# Registering Language Protocol Server

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

More information on how to register different language server protocols can be found at the [wiki](https://github.com/prabirshrestha/vim-lsp/wiki/Servers).

## Autocomplete

`vim-lsp` by default doesn't support any auto complete plugins. You need to install additional plugins to enable auto complete.

### [asyncomplete.vim](https://github.com/prabirshrestha/asyncomplete.vim)

[asyncomplete.vim](https://github.com/prabirshrestha/asyncomplete.vim) is a async auto complete plugin for vim8 and neovim written in pure vim script without any python dependencies.

```viml
Plug 'prabirshrestha/asyncomplete.vim'
Plug 'prabirshrestha/asyncomplete-lsp.vim'
```
