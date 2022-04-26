function! lsp#utils#args#_parse(args, opt) abort
    let l:args = []
    let l:options = {}
    for l:item in split(a:args, ' ')
        let l:parts = matchlist(l:item, '^--\([a-z][a-z0-9-]*\)\(=\S*\)\?$')
        if empty(l:parts)
          call add(l:args, l:item)
          continue
        endif
        let l:key = l:parts[1]
        let l:value = l:parts[2][1:]
        if has_key(a:opt, l:key)
            if has_key(a:opt[l:key], 'type')
                let l:type = a:opt[l:key]['type']
                if l:type == type(v:true)
                    if l:value ==# 'false' || l:value ==# '0'
                        let l:value = 0
                    else
                        let l:value = 1
                    endif
                elseif l:type ==# type(0)
                    let l:value = str2nr(l:value)
                endif
            endif
        endif
        let l:options[l:key] = l:value
    endfor
    return {'args': l:args, 'options': l:options}
endfunction
