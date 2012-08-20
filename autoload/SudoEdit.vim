" SudoEdit.vim - Use sudo/su for writing/reading files with Vim
" ---------------------------------------------------------------
" Version:  0.17
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Mon, 20 Aug 2012 19:30:22 +0200
" Script:  http://www.vim.org/scripts/script.php?script_id=2709 
" License: VIM License
" GetLatestVimScripts: 2709 17 :AutoInstall: SudoEdit.vim

" Functions: "{{{1

fu! <sid>Init() "{{{2
" Which Tool for super-user access to use
" Will be tried in order, first tool that is found will be used
" (e.g. you could use ssh)
" You can specify one in your .vimrc using the
" global variable g:sudoAuth
    if !exists("s:AuthTool")
	let s:sudoAuth=" sudo su "
	if has("mac") || has("macunix")
	    let s:sudoAuth = "security". s:sudoAuth
	elseif has("gui_win32")
	    let s:sudoAuth = "runas elevate". s:sudoAuth
	endif
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
	    call <sid>echoWarn("No authentication tool found, aborting!")
	    finish
	endif

	if s:AuthTool[0] == "su" && empty(s:sudoAuthArg)
	    let s:sudoAuthArg="-c"
	elseif s:AuthTool[0] == "security" && empty(s:sudoAuthArg)
	    let s:sudoAuthArg="execute-with-privileges"
	elseif s:AuthTool[0] == "runas" && empty(s:sudoAuthArg)
	    let s:sudoAuthArg = "/noprofile /user:Administrator"
	endif
	call <sid>SudoAskPasswd()
	call add(s:AuthTool, s:sudoAuthArg . " ")
    endif
    " Stack of messages
    let s:msg = []
endfu

fu! <sid>LocalSettings(setflag, readflag) "{{{2
    if a:setflag
	" Set shellrediraction temporarily
	" This is used to get su working right!
	let s:o_srr = &srr
	" avoid W11 warning
	let s:o_ar  = &l:ar
	let &srr = '>'
	setl ar
	call <sid>Init()
    else
	" Reset old settings
	" shellredirection
	let &srr  = s:o_srr
	" Make sure, persistent undo information is written
	" but only for valid files and not empty ones
	let file=substitute(expand("%"), '^sudo:', '', '')
	if has("persistent_undo")
	    let undofile = undofile(file)
	    if !empty(file) &&
		\!<sid>CheckNetrwFile(@%) && !empty(undofile) &&
		\ &l:udf
		if !a:readflag
		    " Force reading in the buffer to avoid stupid W13 warning
		    " don't do this in GUI mode, so one does not have to enter
		    " the password again (Leave the W13 warning)
		    if !has("gui_running") && s:new_file
			"sil call <sid>SudoRead(file)
			" Be careful, :e! within a BufWriteCmd can crash Vim!
			exe "e!" file
		    endif
		    if empty(glob(undofile)) &&
			\ &undodir =~ '^\.\($\|,\)'
			" Can't create undofile
			call add(s:msg, "Can't create undofile in current " .
			    \ "directory, skipping writing undofiles!")
			return
		    endif
		    call <sid>Exec("wundo! ". fnameescape(undofile(file)))
		    if empty(glob(fnameescape(undofile(file))))
			" Writing undofile not possible 
			call add(s:msg,  "Error occured, when writing undofile" .
			    \ v:exception)
			return
		    endif
		    if (has("unix") || has("macunix")) && !empty(undofile)
			let ufile = string(shellescape(undofile, 1))
			let perm = system("stat -c '%u:%g' " .
				\ shellescape(file, 1))[:-2]
			" Make sure, undo file is readable for current user
			let cmd  = printf("!%s sh -c 'test -f %s && ".
				    \ "chown %s -- %s && ",
				    \ join(s:AuthTool, ' '), ufile, perm, ufile)
			let cmd .= printf("chmod a+r -- %s 2>/dev/null'", ufile)
			if has("gui_running")
			    call <sid>echoWarn("Enter password again for".
				\ " setting permissions of the undofile")
			endif
			call <sid>Exec(cmd)
			"call system(cmd)
		    endif
		endif
	    endif
	endif " has("persistent_undo")
	" Make sure W11 warning is triggered and consumed by 'ar' setting
	checktime
	" Reset autoread option
	let &l:ar = s:o_ar
    endif
endfu

fu! <sid>CheckAuthTool(Authlist) "{{{2
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
    sil %d _
    if has("gui_win32")
	let cmd='"type '. shellescape(a:file,1). '"'
    else
	let cmd='cat ' . shellescape(a:file,1) . ' 2>/dev/null'
    endif
    if  s:AuthTool[0] =~ '^su$'
        let cmd='"' . cmd . '" --'
    endif
    let cmd=':0r! ' . join(s:AuthTool, ' ') . cmd
    call <sid>Exec(cmd)
    if v:shell_error
	echoerr "Error reading ". a:file . "! Password wrong?"
	throw /sudo:readError/
    endif
    sil $d _
    if has("persistent_undo")
	" Force reading undofile, if one exists
	if filereadable(undofile(a:file))
	    exe "sil rundo" escape(undofile(a:file), '%')
	endif
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
	if has("gui_w32")
	    let cmd='"type >'. shellescape(a:file,1). '"'
	else
	    let cmd='tee >/dev/null ' . shellescape(a:file,1)
	endif
	let cmd=a:firstline . ',' . a:lastline . 'w !' .
	    \ join(s:AuthTool, ' ') . cmd
    endif
    if <sid>CheckNetrwFile(a:file) && exists(":NetUserPass") == 2
	let protocol = matchstr(a:file, '^[^:]:')
	call <sid>echoWarn('Using Netrw for writing')
	let uid = input(protocol . ' username: ')
	let passwd = inputsecret('password: ')
	call NetUserPass(uid, passwd)
	" Write using Netrw
	w
    else
	let s:new_file = 0
	if empty(glob(a:file))
	    let s:new_file = 1
	endif
	call <sid>Exec(cmd)
    endif
    if v:shell_error
	if exists("g:sudoDebug") && g:sudoDebug
	    call <sid>echoWarn(v:shell_error)
	endif
	throw "sudo:writeError"
    endif
    " Write successful
    if &mod
	setl nomod
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
    let file = expand(a:file)
    if file =~ '^sudo:'
	let s:use_sudo_protocol_handler = 1
	let file = substitute(file, '^sudo:', '', '')
    endif
    let file = empty(a:file) ? expand("%") : file
    if empty(file)
	call <sid>echoWarn("Cannot write file. Please enter filename for writing!")
	call <sid>LocalSettings(0, 1)
	return
    endif
    try
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
	    exe a:firstline . ',' . a:lastline . 'call <sid>SudoWrite('.
		\ shellescape(file,1) . ')'
	    call add(s:msg, <sid>Stats(file))
	endif
    catch /sudo:writeError/
	call <sid>Exception("There was an error writing the file!")
	call <sid>Mes(s:msg)
	return
    catch /sudo:readError/
	call <sid>Exception("There was an error reading the file ". file. " !")
	call <sid>Mes(s:msg)
	return
    finally
	call <sid>LocalSettings(0, a:readflag)
    endtry
    if file !~ 'sudo:' && s:use_sudo_protocol_handler
	let file = 'sudo:' . fnamemodify(file, ':p')
    endif
    if s:use_sudo_protocol_handler ||
	    \ empty(expand("%")) ||
	    \ file != expand("%")
	exe ':sil f ' . file
	filetype detect
    endif
    call <sid>Mes(s:msg)
endfu

fu! <sid>Mes(msg) "{{{2
    if !empty(s:msg)
	redr!
    else
	return
    endif
    for mess in a:msg
	echom mess
    endfor
    let s:msg=[]
endfu

fu! <sid>Exception(msg) "{{{2
    echoerr v:errmsg
    echoerr a:msg
endfu

fu! <sid>CheckNetrwFile(file) "{{{2
    return a:file =~ '^\%(dav\|fetch\|ftp\|http\|rcp\|rsync\|scp\|sftp\):'
endfu

fu! <sid>SudoAskPasswd() "{{{2
    if s:AuthTool[0] != 'sudo' ||
	\ s:AuthTool[0] =~ 'SUDO_ASKPASS' ||
	\ ( exists("g:sudo_no_gui") && g:sudo_no_gui == 1) ||
	\ !has("unix") ||
	\ !exists("$DISPLAY")
	return
    endif

    let askpwd = ["/usr/lib/openssh/gnome-ssh-askpass",
		\ "/usr/bin/ksshaskpass",
		\ "/usr/lib/ssh/x11-ssh-askpass" ]
    if exists("g:sudo_askpass")
	let askpwd = insert(askpwd, g:sudo_askpass, 0)
    endif
    let sudo_arg = '-A'
    let sudo_askpass = expand("$SUDO_ASKPASS")
    if sudo_askpass != "$SUDO_ASKPASS"
	let list = [ sudo_askpass ] + askpwd
    else
	let list = askpwd
    endif
    for item in list
	if executable(item)
	    " give environment value to sudo, so -A knows
	    " which program to call
	    if (s:AuthTool[0] !~ 'SUDO_ASKPASS')
		call insert(s:AuthTool, 'SUDO_ASKPASS='.shellescape(item,1), 0)
		call add(s:AuthTool, '-A')
	    endif
	endif
    endfor
endfu

fu! <sid>Exec(cmd) "{{{2
    let cmd = a:cmd
    if exists("g:sudoDebug") && g:sudoDebug
	let cmd = substitute(a:cmd, '2>/dev/null', '', 'g')
	let cmd = 'verb '. cmd
	call <sid>echoWarn(cmd)
	exe cmd
	" Allow the user to read messages
	sleep 3
    else
	if has("gui_running")
	    exe cmd
	else
	    silent exe cmd
	endif
    endif
endfu
" Modeline {{{1
" vim: set fdm=marker fdl=0 :  }}}
