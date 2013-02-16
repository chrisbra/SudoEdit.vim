" SudoEdit.vim - Use sudo/su for writing/reading files with Vim
" ---------------------------------------------------------------
" Version:  0.18
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Sat, 16 Feb 2013 23:15:51 +0100
" Script:  http://www.vim.org/scripts/script.php?script_id=2709 
" License: VIM License
" GetLatestVimScripts: 2709 18 :AutoInstall: SudoEdit.vim

" Functions: "{{{1

let s:dir=fnamemodify(expand("<sfile>"), ':p:h')

fu! <sid>Init() "{{{2
" Which Tool for super-user access to use
" Will be tried in order, first tool that is found will be used
" (e.g. you could use ssh)
" You can specify one in your .vimrc using the
" global variable g:sudoAuth

"    each time check, whether the authentication
"    method changed (e.g. the User set a variable)
"    if !exists("s:AuthTool") 
        let s:sudoAuth=" sudo su "
        if <sid>Is("mac")
            let s:sudoAuth = "security ". s:sudoAuth
        elseif <sid>Is("win")
            let s:sudoAuth = "runas elevate ". s:sudoAuth
        endif
        if exists("g:sudoAuth")
            let s:sudoAuth = g:sudoAuth .' '. s:sudoAuth 
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
            throw "sudo:noTool"
        endif
        if s:AuthTool[0] == "su" && empty(s:sudoAuthArg)
            let s:sudoAuthArg="-c"
        elseif s:AuthTool[0] == "security" && empty(s:sudoAuthArg)
            let s:sudoAuthArg="execute-with-privileges"
        elseif s:AuthTool[0] == "runas" && empty(s:sudoAuthArg)
            let s:sudoAuthArg = "/noprofile /user:\"Administrator\""
        endif
        if <sid>Is("win")
            if !exists("s:writable_file")
                " Write into public directory so everybody can access it
                " easily
                let s:writable_file = (empty(expand("$PUBLIC")) ? 
                            \ expand("$TEMP") : expand("$PUBLIC") ).
                            \ '\vim_temp.txt'
                let s:writable_file = shellescape(fnamemodify(s:writable_file, ':p:8'))
            endif
        else
            let s:writable_file = tempname()
        endif

        call <sid>SudoAskPasswd()
        call add(s:AuthTool, s:sudoAuthArg . " ")
        if !exists("s:error_dir")
            let s:error_dir = shellescape(tempname())
            call <sid>Mkdir(s:error_dir)
            let s:error_file = s:error_dir. '/error'
            if <sid>Is("win")
                let s:error_file = s:error_dir. '\error'
                let s:error_file = fnamemodify(s:error_file, ':p:8')
            endif
        endif
"    endif
    " Stack of messages
    let s:msg = []
endfu

fu! <sid>Mkdir(dir) "{{{2
    " First remove the directory, it might still be there from last call
    call SudoEdit#Rmdir(a:dir)
    call system("mkdir ". a:dir)
    " Clean up on Exit
    if !exists('#SudoEditExit#VimLeave')
        augroup SudoEditExit
            au!
            " Clean up when quitting Vim
            exe "au VimLeave * :call SudoEdit#Rmdir('".a:dir. "')"
        augroup END
    endif
endfu

fu! <sid>LocalSettings(values, readflag) "{{{2
    if empty(a:values)
    " Set shellrediraction temporarily
    " This is used to get su working right!
    let o_srr = &srr
    " avoid W11 warning
    let o_ar  = &l:ar
    let &srr = '>'
    setl ar
    let o_tti = &t_ti
    let o_tte = &t_te
    " Turn off screen switching
    set t_ti= t_te=
    call <sid>Init()
    return [o_srr, o_ar, o_tti, o_tte]
    else
    " Make sure, persistent undo information is written
    " but only for valid files and not empty ones
    let file=substitute(expand("%"), '^sudo:', '', '')
    try
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
                throw "sudo:undofileError"
            endif
            call <sid>Exec("wundo! ". fnameescape(undofile(file)))
            if empty(glob(fnameescape(undofile(file))))
                " Writing undofile not possible 
                call add(s:msg,  "Error occured, when writing undofile")
                return
            endif
            if <sid>is("unix") && !empty(undofile)
                let ufile = string(shellescape(undofile, 1))
                let perm = system("stat -c '%u:%g' " .
                    \ shellescape(file, 1))[:-2]
                " Make sure, undo file is readable for current user
                let cmd  = printf("!%s sh -c 'test -f %s && ".
                    \ "chown %s -- %s && ",
                    \ join(s:AuthTool, ' '), ufile, perm, ufile)
                let cmd .= printf("chmod a+r -- %s 2>%s'", ufile, s:error_file)
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
    catch
        " no-op
    finally
        " Make sure W11 warning is triggered and consumed by 'ar' setting
        checktime
        " Reset old settings
        " shellredirection
        let &srr  = a:values[0]
        " Screen switchting codes
        let [ &t_ti, &t_te ] = a:values[2:3]
        " Reset autoread option
        let &l:ar = a:values[1]
    endtry
    endif
endfu

fu! <sid>CheckAuthTool(Authlist) "{{{2
    for tool in a:Authlist
        if executable(tool) ||
        \   (tool == 'uac' && <sid>Is("win")) "enable experimental support for UAC on windows
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
    if <sid>Is("win")
        let file=shellescape(fnamemodify(a:file, ':p:8'))
        let cmd= '!'. s:dir.'\sudo.cmd dummy read '. file. 
            \ ' '. s:writable_file.  ' '.
            \ join(s:AuthTool, ' ')
    else
        let cmd='cat ' . shellescape(a:file,1) . ' 2>'. s:error_file
        if  s:AuthTool[0] =~ '^su$'
            let cmd='"' . cmd . '" --'
        endif
        let cmd=':0r! ' . join(s:AuthTool, ' ') . cmd
    endif
    call <sid>Exec(cmd)
    if v:shell_error
        echoerr "Error reading ". a:file . "! Password wrong?"
        throw "sudo:readError"
    endif
    if <sid>Is("win")
        if !filereadable(s:writable_file[1:-2])
            call add(s:msg, "Temporary file ". s:writable_file. 
                        \ " does not exist. Probably access was denied!")
            throw "sudo:readError"
        else
            exe ':0r ' s:writable_file[1:-2]
        endif
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
    if  s:AuthTool[0] == 'su'
    " Workaround since su cannot be run with :w !
        exe a:firstline . ',' . a:lastline . 'w! ' . s:writable_file
        let cmd=':!' . join(s:AuthTool, ' ') . '"mv ' . s:writable_file . ' ' .
            \ shellescape(a:file,1) . '" --'
    else
        if <sid>Is("win")
            exe a:firstline . ',' . a:lastline . 'w! ' . s:writable_file[1:-2]
            let cmd= '!'. s:dir.'\sudo.cmd dummy write '. shellescape(fnamemodify(a:file, ':p:8')).
                \ ' '. s:writable_file. ' '. join(s:AuthTool, ' ')
        else
            let cmd=printf('tee >/dev/null 2>%s %s',s:error_file, shellescape(a:file,1))
            let cmd=a:firstline . ',' . a:lastline . 'w !' .
            \ join(s:AuthTool, ' ') . cmd
        endif
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

fu! <sid>Is(os) "{{{2
    if (a:os == "win")
        return has("win32") || has("win16") || has("win64")
    elseif (a:os == "mac")
        return has("mac") || has("macunix")
    elseif (a:os == "unix")
        return has("unix") || has("macunix")
    endif
endfu

fu! <sid>Mes(msg) "{{{2
    if !(exists("g:sudoDebug") && g:sudoDebug)
        redr!
        if empty(s:msg)
            return
        endif
    endif
    for mess in a:msg
        echo mess
    endfor
    let s:msg=[]
endfu

fu! <sid>Exception(msg) "{{{2
    echohl Error
    echomsg a:msg
    if exists("g:sudoDebug") && g:sudoDebug
        echo v:throwpoint
    else
        echohl Normal
        call input("Hit enter to continue")
    endif
    echohl Normal
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
                return
            endif
        endif
    endfor
endfu

fu! <sid>Exec(cmd) "{{{2
    let cmd = a:cmd
    if exists("g:sudoDebug") && g:sudoDebug
        let cmd = substitute(a:cmd, '2>'.s:error_file, '', 'g')
        let cmd = 'verb '. cmd
        call <sid>echoWarn(cmd)
        exe cmd
    " probably hit-enter prompt is shown
    else
        if has("gui_running")
            exe cmd
        else
            silent exe cmd
            " avoid hit-enter prompt
            redraw!
        endif
    endif
    if filereadable(s:error_file) && getfsize(s:error_file) > 0
        let error=readfile(s:error_file)
        call add(s:msg, join(error, "\n"))
        call delete(s:error_file)
    endif
endfu
fu! SudoEdit#Rmdir(dir) "{{{2
    if <sid>Is("win")
        sil! call system("rd /s /q ". a:dir)
    else
        sil! call system("rm -rf -- ". a:dir)
    endif
endfu

fu! SudoEdit#SudoDo(readflag, force, file) range "{{{2
    try
        let _settings=<sid>LocalSettings([], 1)
    catch /sudo:noTool/
        call <sid>LocalSettings(_settings, a:readflag)
        return
    endtry
    let s:use_sudo_protocol_handler = 0
    if empty(a:file)
        let file = expand("%")
    else
        let file = expand(a:file)
        if empty(file)
            let file = a:file " expand() might fail (issue #17)
        endif
        if file =~ '^sudo:'
            let s:use_sudo_protocol_handler = 1
            let file = substitute(file, '^sudo:', '', '')
        endif
        let file = fnamemodify(file, ':p')
    endif
    if empty(file)
        call <sid>echoWarn("Cannot write file. Please enter filename for writing!")
        call <sid>LocalSettings(_settings, 1)
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
            if !&mod && empty(a:force)
                call <sid>echoWarn("Buffer not modified, not writing!")
                return
            endif
            exe a:firstline . ',' . a:lastline . 'call <sid>SudoWrite(file)'
            call add(s:msg, <sid>Stats(file))
        endif
    catch /sudo:writeError/
        call <sid>Exception("There was an error writing the file!")
        return
    catch /sudo:readError/
        call <sid>Exception("There was an error reading the file ". file. " !")
        return
    finally
        " Delete temporary file
        call delete(s:writable_file)
        call <sid>LocalSettings(_settings, a:readflag)
        call <sid>Mes(s:msg)
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
endfu

" Modeline {{{1
" vim: set fdm=marker fdl=0 ts=4 sts=4 sw=4 et:  }}}
