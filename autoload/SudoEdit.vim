" SudoEdit.vim - Use sudo/su for writing/reading files with Vim
" ---------------------------------------------------------------
" Version:  0.20
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Thu, 27 Mar 2014 23:19:50 +0100
" Script:  http://www.vim.org/scripts/script.php?script_id=2709 
" License: VIM License
" GetLatestVimScripts: 2709 20 :AutoInstall: SudoEdit.vim

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
                let s:writable_file = (empty($PUBLIC) ? $TEMP : $PUBLIC ).
                            \ '\vim_temp.txt'
                let s:writable_file = shellescape(fnamemodify(s:writable_file, ':p:8'))
            endif
        else
            if !exists("s:writable_file")
                let s:writable_file = tempname()
            endif
        endif

        call <sid>SudoAskPasswd()
        call add(s:AuthTool, s:sudoAuthArg . " ")
        if !exists("s:error_dir")
            let s:error_dir = tempname()
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
    let dir = shellescape(a:dir)
    call SudoEdit#Rmdir(dir)
    call system("mkdir ". dir)
    " Clean up on Exit
    if !exists('#SudoEditExit#VimLeave')
        augroup SudoEditExit
            au!
            " Clean up when quitting Vim
            exe "au VimLeave * :call SudoEdit#Rmdir(".dir. ")"
        augroup END
    endif
endfu

fu! <sid>LocalSettings(values, readflag, file) "{{{2
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
        " avoid a problem with noshelltemp #32
        let o_stmp = &stmp
        setl stmp
        " Set shell to something sane (zsh, doesn't allow to override files using
        " > redirection, issue #24, hopefully POSIX sh works everywhere)
        let o_shell = &shell
        if !<sid>Is("win")
            set shell=sh
        endif
        call <sid>Init()
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
        return [o_srr, o_ar, o_tti, o_tte, o_shell, o_stmp, file]
    else
        " Make sure, persistent undo information is written
        " but only for valid files and not empty ones
        let file=a:values[-1]
        try
            if exists("s:skip_wundo") && s:skip_wundo
                return
            endif
            if has("persistent_undo")
            let undofile = undofile(file)
            if !empty(file) &&
                \!<sid>CheckNetrwFile(@%) && !empty(undofile) &&
                \ &l:udf
                if !a:readflag
                " Force reading in the buffer to avoid stupid W13 warning
                " don't do this in GUI mode, so one does not have to enter
                " the password again (Leave the W13 warning)
                if !has("gui_running") && exists("s:new_file") && s:new_file
                    "sil call <sid>SudoRead(file)
                    " Be careful, :e! within a BufWriteCmd can crash Vim!
                    exe "e!" file
                endif
                call <sid>Exec("wundo! ". fnameescape(undofile(file)))
                if empty(glob(fnameescape(undofile))) &&
                    \ &undodir =~ '^\.\($\|,\)'
                    " Can't create undofile
                    call add(s:msg, "Can't create undofile in current " .
                    \ "directory, skipping writing undofiles!")
                    throw "sudo:undofileError"
                elseif empty(glob(fnameescape(undofile(file))))
                    " Writing undofile not possible 
                    call add(s:msg,  "Error occured, when writing undofile")
                    return
                endif
                if <sid>Is("unix") && !empty(undofile) && s:error_exists == 0
                    let ufile = string(shellescape(undofile, 1))
                    let perm = system("stat -c '%u:%g' " .
                        \ shellescape(file, 1))[:-2]
                    " Make sure, undo file is readable for current user
                    let cmd  = printf("!%s sh -c 'test -f %s && ".
                        \ "chown %s -- %s && ",
                        \ join(s:AuthTool, ' '), ufile, perm, ufile)
                    let cmd .= printf("chmod a+r -- %s 2>%s'", ufile, shellescape(s:error_file))
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
            " Screen switchting codes, and shell
            let [ &t_ti, &t_te, &shell, &stmp ] = a:values[2:5]
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

fu! <sid>Path(cmd) "{{{2
    if exists("g:sudo_{a:cmd}")
        return g:sudo_{a:cmd}
    endif
    return a:cmd
endfu

fu! <sid>SudoRead(file) "{{{2
    sil %d _
    if <sid>Is("win")
        let file=shellescape(fnamemodify(a:file, ':p:8'))
        let cmd= '!'. s:dir.'\sudo.cmd read '. file. 
            \ ' '. s:writable_file.  ' '.
            \ join(s:AuthTool, ' ')
    else
        let cmd='cat ' . shellescape(a:file,1) . ' 2>'. shellescape(s:error_file)
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
    if bufloaded(s:writable_file)
        " prevent E139 error
        exe "bw!" s:writable_file
    endif
    if  s:AuthTool[0] == 'su'
    " Workaround since su cannot be run with :w !
        exe "sil keepalt noa ". a:firstline . ',' . a:lastline . 'w! ' . s:writable_file
        let cmd=':!' . join(s:AuthTool, ' ') . '"mv ' . s:writable_file . ' ' .
            \ shellescape(a:file,1) . '" -- 2>' . shellescape(s:error_file)
    else
        if <sid>Is("win")
            exe 'sil keepalt noa '. a:firstline . ',' . a:lastline . 'w! ' . s:writable_file[1:-2]
            let cmd= '!'. s:dir.'\sudo.cmd write '. shellescape(fnamemodify(a:file, ':p:8')).
                \ ' '. s:writable_file. ' '. join(s:AuthTool, ' ')
        else
            let cmd=printf('%s >/dev/null 2>%s %s', <sid>Path('tee'),
                \ shellescape(s:error_file), shellescape(a:file,1))
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
        call <sid>SetBufName(a:file)
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
    if len($SUDO_ASKPASS)
        let list = [ $SUDO_ASKPASS ] + askpwd
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
        " On Windows, s:error_file could be something like
        " c:\Users\cbraba~1\... and one needs to escape the '~'
        let cmd = substitute(a:cmd, '2>'.escape(shellescape(s:error_file), '~'), '', 'g')
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
        let s:msg += error
        call delete(s:error_file)
    endif
endfu
fu! <sid>SetBufName(file) "{{{2
    if bufname('') !=# fnameescape(a:file)
        " don't give the "ATTENTION" message when an existing swap file is
        " found.
        let sshm = &shortmess
        set shortmess+=A
        exe "sil f" fnameescape(a:file)
        let &shortmess = sshm
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
        let _settings=<sid>LocalSettings([], 1, a:file)
    catch /sudo:noTool/
        call <sid>LocalSettings(_settings, a:readflag, '')
        return
    endtry
    let s:use_sudo_protocol_handler = 0
    let file = _settings[-1]
    if empty(file)
        call <sid>echoWarn("Cannot write file. Please enter filename for writing!")
        call <sid>LocalSettings(_settings, 1, '')
        return
    endif
    try
        if a:readflag
            if !&mod || !empty(a:force)
                call <sid>SudoRead(file)
            else
                call add(s:msg, "Buffer modified, not reloading!")
                throw "sudo:BufferNotModified"
            endif
        else
            exe a:firstline . ',' . a:lastline . 'call <sid>SudoWrite(file)'
            call <sid>SetBufName(a:file)
            call add(s:msg, <sid>Stats(file))
        endif
    catch /sudo:writeError/
        " output error message (only the last line)
        if !empty(s:msg)
            call <sid>Exception("There was an error writing the file! ".
                    \ substitute(s:msg[-1], "\n(.*)$", "\1", ''))
        endif
        let s:skip_wundo = 1
        return
    catch /sudo:readError/
        if !empty(s:msg)
            " output error message (only the last line)
            call <sid>Exception("There was an error reading the file ". file. " !". 
                        \ substitute(s:msg[-1], "\n(.*)$", "\1", ''))
        endif
        " skip writing the undofile, it will most likely also fail.
        let s:skip_wundo = 1
        return
    catch /sudo:BufferNotModified/
        let s:skip_wundo = 1
        return
    finally
        " Delete temporary file
        call delete(s:writable_file)
        call <sid>LocalSettings(_settings, a:readflag, '')
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
