" Converts a markdown language (```foo) to the corresponding Vim filetype
function! s:get_vim_filetype(lang_markdown) abort
    " If the user hasn't customised markdown fenced languages, just return the
    " markdown language
    if !exists('g:markdown_fenced_languages')
        return a:lang_markdown
    endif

    " Otherwise, check if it has an entry for the given language
    for l:type in g:markdown_fenced_languages
        let l:vim_type = substitute(matchstr(l:type, '[^=]*$'), '\..*', '', '')
        let l:markdown_type = matchstr(l:type, '[^=]*')

        if l:markdown_type ==# a:lang_markdown
            " Found entry
            return l:vim_type
        endif
    endfor

    " Not found
    return a:lang_markdown
endfunction

function! s:do_highlight() abort
    if exists('b:lsp_syntax_highlights')
        for l:entry in b:lsp_syntax_highlights
            let l:line = l:entry['line']
            let l:lang = l:entry['language']
            let l:ft = s:get_vim_filetype(l:lang)

            execute printf('syntax match markdownHighlight%s contains=@markdownHighlight%s /^\%%%sl.*$/', l:ft, l:ft, l:line)
        endfor
    endif
endfunction

function! s:cleanup_markdown() abort
    " Don't highlight _ in words
    syntax match markdownError "\w\@<=\w\@="

    " Conceal escaped characters
    " Workaround for: https://github.com/palantir/python-language-server/issues/386
    if has('conceal')
        for l:escaped_char in ['`', '*', '_', '{', '}', '(', ')', '<', '>', '#', '+', '.', '!', '-']
            execute printf('syntax region vimLspMarkdownEscape matchgroup=Conceal start="\\\ze[%s]" end="[%s]\zs" concealends', l:escaped_char, l:escaped_char)
        endfor
    end
endfunction

call s:do_highlight()
call s:cleanup_markdown()
