function! lsp#utils#args#_parse(args, opt) abort
    let l:result = {}
    for l:item in split(a:args, ' ')
        let [l:key, l:value] = split(l:item, '=')
        let l:key = l:key[1:]
        if has_key(a:opt, l:key)
            if has_key(a:opt[l:key], 'type')
                let l:type = a:opt[l:key]['type']
                if l:type == type(v:true)
                    if l:value ==# 'false' || l:value ==# '0' || l:value ==# ''
                        let l:value = 0
                    else
                        let l:value = 1
                    endif
                elseif l:type ==# type(0)
                    let l:value = str2nr(l:value)
                endif
            endif
        endif
        let l:result[l:key] = l:value
    endfor
    return l:result
endfunction
