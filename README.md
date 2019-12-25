# vim-lsp [![Gitter](https://badges.gitter.im/vimlsp/community.svg)](https://gitter.im/vimlsp/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

Async [Language Server Protocol](https://github.com/Microsoft/language-server-protocol) plugin for vim8 and neovim.

# Installing

```viml
Plug 'prabirshrestha/async.vim'
Plug 'prabirshrestha/vim-lsp'
```

_Note: [async.vim](https://github.com/prabirshrestha/async.vim) is required and is used to normalize jobs between vim8 and neovim._

## Registering servers

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

Refer to [vim-lsp-settings](https://github.com/mattn/vim-lsp-settings) on how to easily setup language servers using vim-lsp automatically.

```viml
Plug 'prabirshrestha/async.vim'
Plug 'prabirshrestha/vim-lsp'
Plug 'mattn/vim-lsp-settings'
```

## auto-complete

Refer to docs on configuring omnifunc or [asyncomplete.vim](https://github.com/prabirshrestha/asyncomplete.vim).

## Snippets
vim-lsp does not support snippets by default. If you want snippet integration, you will first have to install a third-party snippet plugin and a plugin that integrates it in vim-lsp.
At the moment, you have two options:
1. [UltiSnips](https://github.com/SirVer/ultisnips) together with [vim-lsp-ultisnips](https://github.com/thomasfaingnaert/vim-lsp-ultisnips)
2. [neosnippet.vim](https://github.com/Shougo/neosnippet.vim) together with [vim-lsp-neosnippet](https://github.com/thomasfaingnaert/vim-lsp-neosnippet)

For more information, refer to the readme and documentation of the respective plugins.

## Folding

You can let the language server automatically handle folding for you. To enable this, you have to set `'foldmethod'`, `'foldexpr'` and (optionally) `'foldtext'`:

```vim
set foldmethod=expr
  \ foldexpr=lsp#ui#vim#folding#foldexpr()
  \ foldtext=lsp#ui#vim#folding#foldtext()
```

If you would like to disable folding globally, you can add this to your configuration:

```vim
let g:lsp_fold_enabled = 0
```

Also see `:h vim-lsp-folding`.

## Supported commands

**Note:**
* Some servers may only support partial commands.
* While it is possible to register multiple servers for the same filetype, some commands will pick only the first server that supports it. For example, it doesn't make sense for rename and format commands to be sent to multiple servers.

| Command | Description|
|--|--|
|`:LspCodeAction`| Gets a list of possible commands that can be applied to a file so it can be fixed (quick fix) |
|`:LspDeclaration`| Go to the declaration of the word under the cursor, and open in the current window |
|`:LspDefinition`| Go to the definition of the word under the cursor, and open in the current window |
|`:LspDocumentDiagnostics`| Get current document diagnostics information |
|`:LspDocumentFormat`| Format entire document |
|`:LspDocumentRangeFormat`| Format document selection |
|`:LspDocumentSymbol`| Show document symbols |
|`:LspHover`| Show hover information |
|`:LspImplementation` | Show implementation of interface in the current window |
|`:LspNextDiagnostic`| jump to next diagnostic (all of error, warning, information, hint) |
|`:LspNextError`| jump to next error |
|`:LspNextReference`| jump to next reference to the symbol under cursor |
|`:LspNextWarning`| jump to next warning |
|`:LspPeekDeclaration`| Go to the declaration of the word under the cursor, but open in preview window |
|`:LspPeekDefinition`| Go to the definition of the word under the cursor, but open in preview window |
|`:LspPeekImplementation`| Go to the implementation of an interface, but open in preview window |
|`:LspPeekTypeDefinition`| Go to the type definition of the word under the cursor, but open in preview window |
|`:LspPreviousDiagnostic`| jump to previous diagnostic (all of error, warning, information, hint) |
|`:LspPreviousError`| jump to previous error |
|`:LspPreviousReference`| jump to previous reference to the symbol under cursor |
|`:LspPreviousWarning`| jump to previous warning |
|`:LspReferences`| Find references |
|`:LspRename`| Rename symbol |
|`:LspStatus` | Show the status of the language server |
|`:LspTypeDefinition`| Go to the type definition of the word under the cursor, and open in the current window |
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

#### Highlights

Highlighting diagnostics requires either NeoVim 0.3+ or Vim with patch 8.1.0579.
They are enabled by default when supported, but can be turned off respectively by

```viml
let g:lsp_highlights_enabled = 0
let g:lsp_textprop_enabled = 0
```

Can be customized by setting or linking `LspErrorHighlight`, `LspWarningHighlight`,
`LspInformationHighlight` and `LspHintHighlight` highlight groups.

#### Virtual text

In NeoVim 0.3 or newer you can use virtual text feature (enabled by default).
You can disable it by adding

```viml
let g:lsp_virtual_text_enabled = 0
```

To your configuration.

Virtual text will use the same highlight groups as signs feature.

### Highlight references

Highlight references to the symbol under the cursor. To enable, set in your
configuration:

```viml
let g:lsp_highlight_references_enabled = 1
```

To change the style of the highlighting, you can set or link the `lspReference`
highlight group, e.g.:

```viml
highlight lspReference ctermfg=red guifg=red ctermbg=green guibg=green
```

## Debugging

In order to enable file logging set `g:lsp_log_file`.

```vim
let g:lsp_log_verbose = 1
let g:lsp_log_file = expand('~/vim-lsp.log')

" for asyncomplete.vim log
let g:asyncomplete_log_file = expand('~/asyncomplete.log')
```
