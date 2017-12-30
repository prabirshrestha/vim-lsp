function! lsp#ui#vim#output#preview(content) abort
    if type(a:content) == type([])
        let l:content = copy(a:content)
    else
        let l:content = split(a:content, "\n")
    endif

    let l:height = min([len(l:content), &previewheight])

    " Close any previously opened preview window
    pclose

    execute l:height.'new'
    setfiletype markdown
    setlocal previewwindow buftype=nofile bufhidden=wipe noswapfile nobuflisted
    setlocal nocursorline nofoldenable

    if has('syntax')
        setlocal nospell
    endif

    for l:line in l:content
        call append(line('$'), l:line)
    endfor

    " Delete first empty line
    0delete

    setlocal readonly nomodifiable
endfunction
