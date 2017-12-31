function! lsp#ui#vim#output#preview(content, ...) abort
    let l:ft = a:0 > 0 ? a:1 : 'markdown'

    if type(a:content) == type([])
        let l:content = copy(a:content)
    else
        let l:content = split(a:content, "\n")
    endif

    let l:height = min([len(l:content), &previewheight])

    " Close any previously opened preview window
    pclose

    execute l:height.'new'

    let &l:filetype = l:ft . '.lsp-hover'

    for l:line in l:content
        call append(line('$'), l:line)
    endfor

    " Delete first empty line
    0delete

    setlocal readonly nomodifiable
endfunction
