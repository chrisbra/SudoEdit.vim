" SudoEdit.vim - Use sudo/su for writing/reading files with Vim
" ---------------------------------------------------------------
" Version:  0.8
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Tue, 20 Apr 2010 00:04:14 +0200


" Script:  http://www.vim.org/scripts/script.php?script_id=2709 
" License: VIM License
" GetLatestVimScripts: 2709 7 :AutoInstall: SudoEdit.vim
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
" Public Interface {{{1
" Define User-Commands and Autocommand "{{{
com! -complete=file -range=% -nargs=? SudoWrite :<line1>,<line2>call SudoEdit#SudoDo(0, <q-args>)
com! -complete=file -nargs=? SudoRead  :call SudoEdit#SudoDo(1, <q-args>)

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
