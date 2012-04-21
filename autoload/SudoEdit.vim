" SudoEdit.vim - Use sudo/su for writing/reading files with Vim
" ---------------------------------------------------------------
" Version:  0.12
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Tue, 31 Jan 2012 22:00:48 +0100
" Script:  http://www.vim.org/scripts/script.php?script_id=2709 
" License: VIM License
" GetLatestVimScripts: 2709 12 :AutoInstall: SudoEdit.vim

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

    let s:AuthTool = <sid>CheckAuthTool(split(s:sudoAuth, '\s'))
    if empty(s:AuthTool)
	finish
    endif

    if s:AuthTool[0] == "su" && empty(s:sudoAuthArg)
	let s:sudoAuthArg="-c"
    endif
    call <sid>SshAskPasswd()
    call add(s:AuthTool, s:sudoAuthArg . " ")
    " Stack of messages
    let s:msg=''
endfu

fu! <sid>LocalSettings(setflag, readflag) "{{{2
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
	    \!<sid>CheckNetrwFile(@%) && !empty(undofile) &&
	    \ &l:udf
	    if !a:readflag
		" Force reading in the buffer to avoid stupid W13 warning
		" don't do this in GUI mode, so one does not have to enter
		" the password again (Leave the W13 warning)
		if !has("gui_running")
		    "sil call <sid>SudoRead(file)
		    exe "e!" file
		endif
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
		    let perm = system("stat -c '%u:%g' " .
			    \ shellescape(file, 1))[:-2]
		    let cmd   = has('gui_running') ? '' : 'sil'
		    let cmd  .= '!' . join(s:AuthTool, ' ').
				\ ' sh -c "chown '.
				\ perm. ' -- '. shellescape(undofile,1) .
				\ ' && '
		    " Make sure, undo file is readable for current user
		    let cmd  .= ' chmod a+r -- '. shellescape(undofile,1).
				\ '" 2>/dev/null'
		    if has("gui_running")
			call <sid>echoWarn("Enter password again for".
			    \ " setting permissions of the undofile")
		    endif
		    exe cmd
		    "call system(cmd)
		endif
	    endif
	endif
    endif
endfu

fu! <sid>CheckAuthTool(Authlist) "{{{2
    if has("mac") || has("macunix")
	" for Mac we hardcode program to use
	return ["security execute-with-privileges"]
    endif
    for tool in a:Authlist
	if executable(tool)
	    return [tool]
	endif
    endfor
    echoerr "No tool found for authentication. Is sudo/su installed and in your $PATH?"
    echoerr "Try setting g:sudoAuth and g:sudoAuthArg"
    return []
endfu

fu! <sid>echoWarn(mess) "{{{2
    echohl WarningMsg
    echomsg a:mess
    echohl Normal
endfu

fu! <sid>SudoRead(file) "{{{2
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
	call <sid>echoWarn(cmd)
	exe cmd
    else
	if has("gui_running")
	    exe cmd
	else
	    silent! exe cmd
	endif
    endif
    $d 
    " Force reading undofile, if one exists
    if filereadable(undofile(a:file))
	exe "sil rundo" escape(undofile(a:file), '%')
    endif
    filetype detect
    set nomod
endfu

fu! <sid>SudoWrite(file) range "{{{2
    if  s:AuthTool[0] =~ '^su$'
	" Workaround since su cannot be run with :w !
	let tmpfile = tempname()
	exe a:firstline . ',' . a:lastline . 'w ' . tmpfile
	let cmd=':!' . join(s:AuthTool, ' ') . '"mv ' . tmpfile . ' ' .
	    \ a:file . '" --'
    else
	let cmd='tee >/dev/null ' . a:file
	let cmd=a:firstline . ',' . a:lastline . 'w !' .
	    \ join(s:AuthTool, ' ') . cmd
    endif
    if <sid>CheckNetrwFile(a:file)
	let protocol = matchstr(a:file, '^[^:]:')
	call <sid>echoWarn('Using Netrw for writing')
	let uid = input(protocol . ' username: ')
	let passwd = inputsecret('password: ')
	call NetUserPass(uid, passwd)
	" Write using Netrw
	w
    else
	if exists("g:sudoDebug") && g:sudoDebug
	    call <sid>echoWarn(cmd)
	    exe cmd
	else
	    if has("gui_running")
		exe cmd
	    else
		silent exe cmd
	    endif
	endif
    endif
    if v:shell_error
	if exists("g:sudoDebug") && g:sudoDebug
	    call <sid>echoWarn(v:shell_error)
	endif
	throw "writeError"
    endif
endfu

fu! <sid>Stats(file) "{{{2
    ":w echoes a string like this by default:
    ""SudoEdit.vim" 108L, 2595C geschrieben
    return '"' . a:file . '" ' . line('$') . 'L, ' . getfsize(expand(a:file)) . 'C written'
endfu

fu! SudoEdit#SudoDo(readflag, force, file) range "{{{2
    call <sid>LocalSettings(1, 1)
    let s:use_sudo_protocol_handler = 0
    let file = a:file
    if file =~ '^sudo:'
	let s:use_sudo_protocol_handler = 1
	let file = substitute(file, '^sudo:', '', '')
    endif
    let file = empty(a:file) ? expand("%") : file
    "let file = !empty(a:file) ? substitute(a:file, '^sudo:', '', '') : expand("%")
    if empty(file)
	call <sid>echoWarn("Cannot write file. Please enter filename for writing!")
	call <sid>LocalSettings(0, 1)
	return
    endif
    if a:readflag
	if !&mod || !empty(a:force)
	    call <sid>SudoRead(file)
	else
	    call <sid>echoWarn("Buffer modified, not reloading!")
	    return
	endif
    else
	if !&mod && !empty(a:force)
	    call <sid>echoWarn("Buffer not modified, not writing!")
	    return
	endif
	try
	    exe a:firstline . ',' . a:lastline . 'call <sid>SudoWrite(' . shellescape(file,1) . ')'
	    let s:msg = <sid>Stats(file)
	catch /writeError/
	    let a=v:errmsg
	    echoerr "There was an error writing the file!"
	    echoerr a
	endtry
    endif
    call <sid>LocalSettings(0, a:readflag)
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
    if s:use_sudo_protocol_handler || empty(expand("%"))
	exe ':sil f ' . file
	filetype detect
    endif
    if !empty(s:msg)
	redr!
	echo s:msg
	let s:msg = ""
    endif
endfu

" Not needed
fu! <sid>SudoWritePrepare(name, line1, line2) "{{{2
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

fu! <sid>SshAskPasswd() "{{{2
    if s:AuthTool[0] != 'sudo' ||
	\ ( exists("g:sudo_no_gui") && g:sudo_no_gui == 1) ||
	\ !has("unix") ||
	\ !exists("$DISPLAY")
	" Todo: What about MacVim?
	return
    endif

    let askpwd = ["/usr/lib/openssh/gnome-ssh-askpass",
		\ "/usr/bin/ksshaskpass",
		\ "/usr/lib/ssh/x11-ssh-askpass" ]
    if exists("g:sudo_askpass")
	let askpwd = insert(askpw, g:sudo_askpass, 0)
    endif
    let sudo_arg = '-A'
    for item in [ "$SUDO_ASKPASS"] + askpwd
	if executable(expand(item))
	    " give environment value to sudo, so -A knows
	    " which program to call
	    call insert(s:AuthTool, 'SUDO_ASKPASS='.shellescape(item,1), 0)
	    call add(s:AuthTool, '-A')
	endif
    endfor
endfu
" Modeline {{{1
" vim: set fdm=marker fdl=0 :  }}}
