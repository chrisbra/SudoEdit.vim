" SudoEdit.vim - Use sudo/su for writing/reading files with Vim
" ---------------------------------------------------------------
" Version:  0.11
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Thu, 15 Dec 2011 15:54:33 +0100
" Script:  http://www.vim.org/scripts/script.php?script_id=2709 
" License: VIM License
" GetLatestVimScripts: 2709 11 :AutoInstall: SudoEdit.vim

" Functions: "{{{1

fu! <sid>Init() "{{{2
" Which Tool for super-user access to use
" Will be tried in order, first tool that is found will be used
" (e.g. you could use ssh)
" You can specify one in your .vimrc using the
" global variable g:sudoAuth
    let s:sudoAuth=" sudo su "
    if exists("g:sudoAuth")
	let s:sudoAuth = g:sudoAuth . s:sudoAuth
    endif

" Specify the parameter to use for the auth tool e.g. su uses "-c", but
" for su, it will be autodetected, sudo does not need one, for ssh use 
" "root@localhost"
"
" You can also use this parameter if you do not want to become root 
" but any other user
"
" You can specify this parameter in your .vimrc using the
" global variable g:sudoAuthArg
    if !exists("g:sudoAuthArg")
	let s:sudoAuthArg=""
    else
	let s:sudoAuthArg=g:sudoAuthArg
    endif

    let s:AuthTool=SudoEdit#CheckAuthTool(split(s:sudoAuth, '\s'))
    if empty(s:AuthTool)
	finish
    endif

    if s:AuthTool[0] == "su" && empty(s:sudoAuthArg)
	let s:sudoAuthArg="-c"
    endif
    call add(s:AuthTool, s:sudoAuthArg . " ")
    " Stack of messages
    let s:msg=''
endfu

fu! SudoEdit#LocalSettings(setflag, readflag) "{{{2
    if a:setflag
	" Set shellrediraction temporarily
	" This is used to get su working right!
	let s:o_srr = &srr
	let &srr = '>'
	call <sid>Init()
    else
	" Reset old settings
	" shellredirection
	let &srr = s:o_srr
	" Make sure, persistent undo information is written
	" but only for valid files and not empty ones
	let file=substitute(expand("%"), '^sudo:', '', '')
	let undofile = undofile(file)
	if has("persistent_undo") && !empty(file) &&
	    \!<sid>CheckNetrwFile(@%) && !empty(undofile)
	    " Force reading in the buffer
	    " to avoid stupid W13 warning
	    if !a:readflag
		sil call SudoEdit#SudoRead(file)
		if empty(glob(undofile)) &&
		    \ &undodir =~ '^\.\($\|,\)'
		    " Can't create undofile
		    let s:msg = "Can't create undofile in current " .
			\ "directory, skipping writing undofiles!"
		    return
		endif
		try
		    exe "sil wundo!" fnameescape(undofile(file))
		catch
		    " Writing undofile not possible 
		    let s:msg = "Error occured, when writing undofile" .
			\ v:exception
		    return
		endtry
		if (has("unix") || has("macunix")) && !empty(undofile)
		    let perm = system("stat -c '%u:%g' " . shellescape(file, 1))[:-2]
		    let cmd  = 'sil !' . join(s:AuthTool, ' '). ' sh -c "chown '.
				\ perm. ' -- '. shellescape(undofile,1) . ' && '
		    " Make sure, undo file is readable for current user
		    let cmd  .= ' chmod a+r -- '. shellescape(undofile,1).
				\ '" 2>/dev/null'
		    exe cmd
		    "call system(cmd)
		endif
	    endif
	endif
    endif
endfu

fu! SudoEdit#CheckAuthTool(Authlist) "{{{2
    for tool in a:Authlist
	if executable(tool)
	    return [tool]
	endif
    endfor
    echoerr "No tool found for authentication. Is sudo/su installed and in your $PATH?"
    echoerr "Try setting g:sudoAuth and g:sudoAuthArg"
    return []
endfu

fu! SudoEdit#echoWarn(mess) "{{{2
    echohl WarningMsg
    echomsg a:mess
    echohl Normal
endfu

fu! SudoEdit#SudoRead(file) "{{{2
    %d
    if !exists("g:sudoDebug")
	let cmd='cat ' . shellescape(a:file,1) . ' 2>/dev/null'
    else
	let cmd='cat ' . shellescape(a:file,1) 
    endif
    if  s:AuthTool[0] =~ '^su$'
        let cmd='"' . cmd . '" --'
    endif
    let cmd=':0r! ' . join(s:AuthTool, ' ') . cmd
    if exists("g:sudoDebug") && g:sudoDebug
	call SudoEdit#echoWarn(cmd)
	exe cmd
    else
	silent! exe cmd
    endif
    $d 
    " Force reading undofile, if one exists
    if filereadable(undofile(a:file))
	exe "sil rundo" escape(undofile(a:file), '%')
    endif
    filetype detect
    set nomod
endfu

fu! SudoEdit#SudoWrite(file) range "{{{2
    if  s:AuthTool[0] =~ '^su$'
	" Workaround since su cannot be run with :w !
	let tmpfile = tempname()
	exe a:firstline . ',' . a:lastline . 'w ' . tmpfile
	let cmd=':!' . join(s:AuthTool, ' ') . '"mv ' . tmpfile . ' ' . a:file . '" --'
    else
	let cmd='tee >/dev/null ' . a:file
	let cmd=a:firstline . ',' . a:lastline . 'w !' . join(s:AuthTool, ' ') . cmd
    endif
    if <sid>CheckNetrwFile(a:file)
	let protocol = matchstr(a:file, '^[^:]:')
	call SudoEdit#echoWarn('Using Netrw for writing')
	let uid = input(protocol . ' username: ')
	let passwd = inputsecret('password: ')
	call NetUserPass(uid, passwd)
	" Write using Netrw
	w
    else
	if exists("g:sudoDebug") && g:sudoDebug
	    call SudoEdit#echoWarn(cmd)
	    exe cmd
	else
	    silent exe cmd
	endif
    endif
    if v:shell_error
	if exists("g:sudoDebug") && g:sudoDebug
	    call SudoEdit#echoWarn(v:shell_error)
	endif
	throw "writeError"
    endif
endfu

fu! SudoEdit#Stats(file) "{{{2
    ":w echoes a string like this by default:
    ""SudoEdit.vim" 108L, 2595C geschrieben
    return '"' . a:file . '" ' . line('$') . 'L, ' . getfsize(expand(a:file)) . 'C written'
endfu

fu! SudoEdit#SudoDo(readflag, file) range "{{{2
    call SudoEdit#LocalSettings(1, 1)
    let s:use_sudo_protocol_handler = 0
    let file = a:file
    if file =~ '^sudo:'
	let s:use_sudo_protocol_handler = 1
	let file = substitute(file, '^sudo:', '', '')
    endif
    let file = empty(a:file) ? expand("%") : file
    "let file = !empty(a:file) ? substitute(a:file, '^sudo:', '', '') : expand("%")
    if empty(file)
	call SudoEdit#echoWarn("Cannot write file. Please enter filename for writing!")
	call SudoEdit#LocalSettings(0, 1)
	return
    endif
    if a:readflag
	call SudoEdit#SudoRead(file)
    else
	if !&mod
	    call SudoEdit#echoWarn("Buffer not modified, not writing")
	    return
	endif
	try
	    exe a:firstline . ',' . a:lastline . 'call SudoEdit#SudoWrite(' . shellescape(file,1) . ')'
	    let s:msg = SudoEdit#Stats(file)
	catch /writeError/
	    let a=v:errmsg
	    echoerr "There was an error writing the file!"
	    echoerr a
	endtry
    endif
    call SudoEdit#LocalSettings(0, a:readflag)
    if file !~ 'sudo:' && s:use_sudo_protocol_handler
	let file = 'sudo:' . fnamemodify(file, ':p')
    endif
    if v:shell_error
	echoerr "Error " . ( a:readflag ? "reading " : "writing to " )  .
		\ file . "! Password wrong?"
    endif
    " Write successfull
    if &mod
	setl nomod
    endif
    exe ':sil f ' . file
    if !empty(s:msg)
	"redr!
	echo s:msg
	let s:msg = ""
    endif
endfu

" Not needed
fu! SudoEdit#SudoWritePrepare(name, line1, line2) "{{{2
    let s:oldpos = winsaveview()
    let name=a:name
    if empty(name)
	let name='""'
    endif
    let cmd = printf("%d,%dcall SudoEdit#SudoDo(0, %s)",
		\ a:line1, a:line2, name)
    exe cmd
    call winrestview(s:oldpos)
endfu

fu! <sid>CheckNetrwFile(file) "{{{2
    return a:file =~ '^\%(dav\|fetch\|ftp\|http\|rcp\|rsync\|scp\|sftp\):'
endfu
" Modeline {{{1
" vim: set fdm=marker fdl=0 :  }}}
