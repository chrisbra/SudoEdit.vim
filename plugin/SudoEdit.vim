" SudoEdit.vim - Use sudo/su for writing/reading files with Vim
" ---------------------------------------------------------------
" Version:  0.17
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Mon, 20 Aug 2012 19:30:22 +0200
" Script:  http://www.vim.org/scripts/script.php?script_id=2709 
" License: VIM License
" GetLatestVimScripts: 2709 17 :AutoInstall: SudoEdit.vim
" Documentation: see :h SudoEdit.txt

" ---------------------------------------------------------------------
" Load Once: {{{1
if exists("g:loaded_sudoedit") || &cp
 finish
endif
let g:loaded_sudoedit = 1
let s:keepcpo          = &cpo
set cpo&vim

if v:version < 700 || ( v:version == 700 && !has("patch111"))
  echomsg 'SudoEdit: You need at least Vim 7.0 with patch111'
  finish
endif

" ---------------------------------------------------------------------
" Functions {{{1
func! <sid>ExpandFiles(A, L, P) "{{{
  if a:A =~ '^s\%[udo:]$'
    return [ "sudo:" ]
  endif
  let pat = matchstr(a:A, '^\(s\%[udo:]\)\?\zs.*')
  let gpat = (pat[0] =~ '[./]' ? pat : '/'.pat). '*'
  if !empty(pat)
    " Patch 7.3.465 introduced the list parameter to glob()
    if v:version > 703 || (v:version == 703 && has('patch465'))
      let res = glob(gpat, 1, 1)
    else
      let res = split(glob(gpat, 1),"\n")
    endif
    call filter(res, '!empty(v:val)')
    call filter(res, 'v:val =~ pat')
    call map(res, 'isdirectory(v:val) ? v:val.''/'':v:val')
    if a:A =~ '^s\%[udo:]'
      call map(res, '''sudo:''.v:val')
    endif
    return res
  else
    return ''
  endif
endfu

" ---------------------------------------------------------------------
" Public Interface {{{1
" Define User-Commands and Autocommand "{{{
"
" Dirty hack, to make winsaveview work, ugly but works.
" because functions with range argument reset the cursor position!
com! -complete=customlist,<sid>ExpandFiles -bang -range=% -nargs=? SudoWrite
      \ :let s:a=winsaveview()|
      \ :<line1>,<line2>call SudoEdit#SudoDo(0, <q-bang>, <q-args>)|
      \ call winrestview(s:a)
com! -complete=customlist,<sid>ExpandFiles -bang -nargs=? SudoRead
      \ :let s:a=winsaveview()|
      \ :call SudoEdit#SudoDo(1, <q-bang>, <q-args>) |
      \ call winrestview(s:a)
" This would be nicer, but look at the function, it isn't really prettier!
"com! -complete=file -range=% -nargs=? SudoWrite
"      \ :call SudoEdit#SudoWritePrepare(<q-args>, <line1>,<line2>)

augroup Sudo
	autocmd!
	au BufReadCmd,FileReadCmd sudo:/*,sudo:* SudoRead <afile>
	au BufWriteCmd,FileWriteCmd sudo:/*,sudo:* SudoWrite <afile>
augroup END
"}}}

" =====================================================================
" Restoration And Modelines: {{{1
let &cpo= s:keepcpo
unlet s:keepcpo

" Modeline {{{1
" vim: fdm=marker sw=2 sts=2 ts=8 fdl=0
