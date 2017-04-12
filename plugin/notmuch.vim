if exists('g:loaded_notmuch')
    finish
endif
let g:loaded_notmuch = 1

if !exists('g:notmuch_default_mappings') || g:notmuch_default_mappings
  augroup notmuch_defaults
    autocmd!
    autocmd FileType notmuch-folders nmap <buffer> <Enter>
      \ :call g:NotmuchShowSearch()<CR>
    autocmd FileType notmuch-search nmap <buffer> <Enter>
      \ :call g:NotmuchShowThread(1)<CR>
    autocmd FileType notmuch-search nmap <buffer> <Space>
      \ :call g:NotmuchShowThread(2)<CR>
    " Open fold, attachment or uri.
    autocmd FileType notmuch-show nmap <buffer> <Enter>
      \ :call g:NotmuchViewMagic()<CR>
    autocmd FileType notmuch-folders,notmuch-search nmap <buffer> s
      \ :call g:NotmuchSearchPrompt()<CR>
    autocmd FileType notmuch-folders,notmuch-search nmap <buffer> <C-r>
      \ :call g:NotmuchRefresh()<CR>
    autocmd BufEnter,WinEnter,BufWinEnter :call g:NotmuchRefresh()<CR>
    autocmd FileType notmuch-folders,notmuch-search,notmuch-show nmap <buffer> c
      \ :call g:NotmuchCompose('')<CR>
    " There should be no need to record macros when viewing mail.
    autocmd FileType notmuch-search,notmuch-show nmap <buffer> q
      \ :call g:NotmuchDeleteBuffer()<CR>
    " Sacrifice backwards search. There's still N.
    autocmd FileType notmuch-search,notmuch-show nmap <buffer> ?
      \ :call g:NotmuchInfo()<CR>
    " No need for maps that are for modification.
    autocmd FileType notmuch-folders,notmuch-search,notmuch-show nmap <buffer> a
      \ :call g:NotmuchTag('')<CR>
    autocmd FileType notmuch-folders,notmuch-search,notmuch-show nmap <buffer> I
      \ :call g:NotmuchTag('-unread')<CR>
    autocmd FileType notmuch-folders,notmuch-search,notmuch-show nmap <buffer> A
      \ :call g:NotmuchTag('-unread -inbox')<CR>
    autocmd FileType notmuch-show nmap <buffer> d :call g:NotmuchDumpMbox()<CR>
    autocmd FileType notmuch-show nmap <buffer> p
      \ :call g:NotmuchSavePatches()<CR>
    autocmd FileType notmuch-show nmap <buffer> r
      \ :call g:NotmuchReply()<CR>
    autocmd FileType notmuch-show nmap <buffer> <S-Tab>
      \ :call g:NotmuchPrevMessage()<CR>
    autocmd FileType notmuch-show nmap <buffer> <Tab>
      \ :call g:NotmuchNextMessage()<CR>
    autocmd FileType notmuch-compose nmap <buffer> ,s
      \ :call g:NotmuchComposeSend()<CR>
    autocmd FileType notmuch-compose nmap <buffer> ,q
      \ :call g:NotmuchComposeAbort()<CR>
    autocmd FileType notmuch-search
      \ nnoremap <buffer> G G:call g:NotmuchRenderMore()<CR>
  augroup END
endif

function! s:InitVariable(variable, value)
  if !exists(a:variable)
    let l:declaration = 'let ' . a:variable . ' = '
    if type(a:value) == 0
      let l:declaration .= a:value
    elseif type(a:value) == 1
      let l:declaration .= "'" . substitute(a:value, "'", "''", 'g') . "'"
    endif
    execute l:declaration
  endif
endfunction

call s:InitVariable('g:notmuch_sendmail_method', 'sendmail')
call s:InitVariable('g:notmuch_sendmail_location', '/usr/bin/msmtp')
call s:InitVariable('g:notmuch_sendmail_arguments', '')
call s:InitVariable('g:notmuch_search_date_format', '%d.%m.%y')
call s:InitVariable('g:notmuch_show_date_format', '%d.%m.%y %H:%M:%S')
call s:InitVariable('g:notmuch_view_attachment', 'xdg-open')
call s:InitVariable('g:notmuch_attachment_dir', '~/.notmuch/tmp')
call s:InitVariable('g:notmuch_save_sent_locally', 1)
call s:InitVariable('g:notmuch_save_sent_mailbox', 'Sent')
call s:InitVariable('g:notmuch_folders_count_threads', 0)
call s:InitVariable('g:notmuch_folders_display_unread_count', 0)
call s:InitVariable('g:notmuch_compose_start_insert', 0)
call s:InitVariable('g:notmuch_show_folded_full_headers', 1)
call s:InitVariable('g:notmuch_show_folded_threads', 1)
call s:InitVariable('g:notmuch_open_uri', 'xdg-open')
call s:InitVariable('g:notmuch_gpg_pinentry', 0)
call s:InitVariable('g:notmuch_gpg_sign', 0)

if !exists('g:notmuch_show_headers')
  let g:notmuch_show_headers = [
    \ 'Subject',
    \ 'To',
    \ 'Cc',
    \ 'Date',
    \ 'Message-Id',
    \ ]
endif

if !exists('g:notmuch_folders')
  let g:notmuch_folders = [
    \ ['new', 'tag:inbox and tag:unread'],
    \ ['inbox', 'tag:inbox'],
    \ ['unread', 'tag:unread'],
    \ ['sent', 'tag:sent']
    \ ]
endif

function! s:NewFileBuffer(type, fname)
  execute printf('edit %s', a:fname)
  execute printf('set filetype=notmuch-%s', a:type)
  execute printf('set syntax=notmuch-%s', a:type)
  ruby $curbuf.init(VIM::evaluate('a:type'))
endfunction

function! s:OnComposeAbort()
  if b:compose_done
    return
  endif
  if input('[s]end/[q]uit? ') =~# '^s'
    call g:NotmuchComposeSend()
  endif
endfunction

function! g:NotmuchComposeAbort()
  let b:compose_done = 1
  call g:NotmuchDeleteBuffer()
endfunction

function! g:NotmuchComposeSend()
  let b:compose_done = 1
  let l:fname = expand('%')
  let l:lines = getline(1, '$')
  let l:failed = 0
ruby << EOF
  begin
    compose_send(VIM::evaluate('l:lines'), VIM::evaluate('l:fname'))
  rescue Exception => e
    VIM::command('let l:failed = 1')
    vim_err("Sending failed. Error message was: #{e.message}")
  end
EOF
  if l:failed == 0
    call g:NotmuchDeleteBuffer()
  endif
endfunction

function! g:NotmuchPrevMessage()
  ruby prev_message()
endfunction

function! g:NotmuchNextMessage(matching_tag)
  ruby next_message(VIM::evaluate('a:matching_tag'))
endfunction

function! s:SetupCompose()
  let b:compose_done = 0
  augroup abort_compose
    autocmd!
    autocmd BufDelete <buffer> call s:OnComposeAbort()
  augroup END
  if g:notmuch_compose_start_insert
    startinsert!
  end
endfunction

function! g:NotmuchReply()
  ruby open_reply(get_message.mail)
  call s:SetupCompose()
endfunction

function! g:NotmuchCompose(to_email)
  call s:NewBuffer('compose')
  ruby open_compose(VIM::evaluate('a:to_email'))
  call s:SetupCompose()
endfunction

function! g:NotmuchInfo()
  if &filetype ==# 'notmuch-show'
    ruby vim_puts get_message.inspect
  elseif &filetype ==# 'notmuch-search'
    ruby vim_puts get_thread_id
endif
endfunction

function! g:NotmuchViewMagic()
  let l:line = getline('.')
  let l:pos = getpos('.')
  let l:lineno = l:pos[1]
  let l:fold = foldclosed(l:lineno)
  ruby view_magic(VIM::evaluate('l:line'), VIM::evaluate('l:lineno'),
      \ VIM::evaluate('l:fold'))
endfunction

function! s:OpenUri()
  let l:line = getline('.')
  let l:pos = getpos('.')
  let l:col = l:pos[2]

  ruby open_uri(VIM::evaluate('l:line'), VIM::evaluate('l:col') - 1)
endfunction

function! g:NotmuchDumpMbox()
  let l:file = input('File name: ')
ruby << EOF
  file = VIM::evaluate('l:file')
  m = get_message
  system "notmuch show --format=mbox id:#{m.message_id} > #{file}"
EOF
endfunction

function! g:NotmuchSavePatches()
  let l:dir = input('Save to directory: ', getcwd(), 'dir')
  ruby save_patches(VIM::evaluate('l:dir'))
endfunction

function! g:NotmuchTag(intags)
  if empty(a:intags)
    let l:tags = input('tags: ')
  else
    let l:tags = a:intags
  endif

  if &filetype ==# 'notmuch-folders'
    let l:choice = confirm('Do you really want to tag all messages in this folder?', "&yes\n&no", 1)
    if l:choice == 1
ruby << EOF
      n = $curbuf.line_number
      s = $searches[n - 1]
      t = VIM::evaluate('l:tags')
      tag(s, t)
EOF
      call g:NotmuchRefresh()
    endif
  elseif &filetype ==# 'notmuch-search'
    ruby tag(get_thread_id, VIM::evaluate('l:tags'))
    " ruby tag($cur_search, VIM::evaluate('l:tags'))
    normal! j
  elseif &filetype ==# 'notmuch-show'
    ruby tag(get_cur_view, VIM::evaluate('l:tags'))
    call s:NextThread()
  endif

endfunction

function! g:NotmuchSearchPrompt()
  let l:text = input('Search: ')
  call s:Search(l:text)
endfunction

function! g:NotmuchRenderMore()
ruby << EOF
  if $render.is_ready?
    VIM::command('setlocal modifiable')
    $render.do_next
    VIM::command('setlocal nomodifiable')
  end
EOF
endfunction

function! g:NotmuchRefresh()
  setlocal modifiable
  ruby $curbuf.reopen
  ruby render()
  setlocal nomodifiable
endfunction

function! s:NextThread()
  call g:NotmuchDeleteBuffer()
  if line('.') != line('$')
    normal! j
    call g:NotmuchShowThread(0)
  else
    echo 'No more messages.'
  endif
endfunction

function! g:NotmuchDeleteBuffer()
ruby << EOF
  $curbuf.close
EOF
  bdelete!
endfunction

function! s:NewBuffer(type)
  enew
  setlocal buftype=nofile bufhidden=hide
  keepjumps 0d
  execute printf('set filetype=notmuch-%s', a:type)
  execute printf('set syntax=notmuch-%s', a:type)
  ruby $curbuf.init(VIM::evaluate('a:type'))
endfunction

function! s:SetMenuBuffer()
  setlocal nomodifiable
  setlocal cursorline
  setlocal nowrap
endfunction

function! s:Show(thread_id, msg_id)
  call s:NewBuffer('show')
  setlocal modifiable
  ruby show(VIM::evaluate('a:thread_id'), VIM::evaluate('a:msg_id'))
  setlocal nomodifiable
  setlocal foldmethod=manual
endfunction

function! g:NotmuchShowThread(mode)
  ruby show_thread(VIM::evaluate('a:mode'))
endfunction

function! s:Search(search)
  call s:NewBuffer('search')
ruby << EOF
  $cur_search = VIM::evaluate('a:search')
  search_render($cur_search)
EOF

  call s:SetMenuBuffer()
endfunction

function! g:NotmuchShowSearch()
ruby << EOF
  n = $curbuf.line_number
  s = $searches[n - 1]
  if s.length > 0
    VIM::command("call s:Search('#{s}')")
  end
EOF
endfunction

function! s:Folders()
  call s:NewBuffer('folders')
  ruby folders_render()
  call s:SetMenuBuffer()
endfunction

let s:plug = expand('<sfile>:h')
let s:script = s:plug . '/notmuch.rb'

function! s:Notmuch(...)
ruby << EOF
  notmuch = VIM::evaluate('s:script')
  require notmuch
EOF
  if a:0
    call s:Search(join(a:000))
  else
    call s:Folders()
  endif
endfunction

command -nargs=* NotMuch call s:Notmuch(<f-args>)
