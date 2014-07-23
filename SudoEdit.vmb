" Vimball Archiver by Charles E. Campbell, Jr., Ph.D.
UseVimball
finish
autoload/SudoEdit.vim	[[[1
499
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
    if  s:AuthTool[0] == 'su'
    " Workaround since su cannot be run with :w !
        exe "noa" a:firstline . ',' . a:lastline . 'w! ' . s:writable_file
        let cmd=':!' . join(s:AuthTool, ' ') . '"mv ' . s:writable_file . ' ' .
            \ shellescape(a:file,1) . '" -- 2>' . shellescape(s:error_file)
    else
        if <sid>Is("win")
            exe 'noa ' a:firstline . ',' . a:lastline . 'w! ' . s:writable_file[1:-2]
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
        let sshm = &shortmess
        set shortmess+=A  " don't give the "ATTENTION" message when an existing swap file is found.
        exe "sil f" fnameescape(a:file)
        let &shortmess = sshm
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
            exe "sil f" fnameescape(a:file)
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
doc/SudoEdit.txt	[[[1
385
*SudoEdit.txt*  Edit Files using Sudo/su

Author:  Christian Brabandt <cb@256bit.org>
Version: Vers 0.20 Thu, 27 Mar 2014 23:19:50 +0100
Copyright: (c) 2009-2013 by Christian Brabandt               *SudoEdit-copyright*
           The VIM LICENSE applies to SudoEdit.vim and SudoEdit.txt
           (see |copyright|) except use SudoEdit instead of "Vim".
           NO WARRANTY, EXPRESS OR IMPLIED.  USE AT-YOUR-OWN-RISK.


==============================================================================
1. Contents                             *SudoEdit* *SudoEdit-contents*

        1.  Contents......................................: |SudoEdit-contents|
        2.  SudoEdit Manual...............................: |SudoEdit-manual|
          1 SudoEdit: SudoRead............................: |SudoRead|
          2 SudoEdit: SudoWrite...........................: |SudoWrite|
        3.  SudoEdit Configuration........................: |SudoEdit-config|
          1 SudoEdit on Windows...........................: |SudoEdit-Win|
        4.  SudoEdit Debugging............................: |SudoEdit-debug|
        5.  SudoEdit F.A.Q................................: |SudoEdit-faq|
        6.  SudoEdit History..............................: |SudoEdit-history|

==============================================================================
2. SudoEdit Manual                                      *SudoEdit-manual*

Functionality

This plugin enables vim to read files, using sudo or su or any other tool that
can be used for changing the authentication of a user. Therefore it needs any
of sudo or su installed and usable by the user. This means, you have to know
the credentials to authenticate yourself as somebody else.

That's why this plugin probably won't work on Windows, but you might be able
to configure it to use a method that works on Windows (see |SudoEdit-config|)

By default SudoEdit will first try to use sudo and if sudo is not found it
will fall back and try to use su. Note, that you might have to configure these
tools, before they can use them successfully.

SudoEdit requires at least a Vim Version 7 with patch 111 installed. Patch 111
introduced the |shellescape()| functionality. On a Mac (using MacVim), it uses
the command "security execute-with-privileges" to query for your password, on
Unix, it can make use of graphical password dialog tools like
ssh-gnome-askpass (see |g:sudo_askpass|)

The SudoEdit Plugin provides 2 Commands:

==============================================================================
2.1 SudoRead                                                     *SudoRead*

        :SudoRead[!] [file]

SudoRead will read the given file name using any of the configured methods for
superuser authtication. It basically does something like this: >

    :r !sudo cat file

If no filename is given, SudoRead will try to reread the current file name.
If the current buffer does not contain any file, it will abort. If the !
argument is used, the current buffer contents will be discarded, if it was
modified.

SudoRead provides file completion, so you can use <Tab> on the commandline to
specify the file to read.

For compatibility with the old sudo.vim Plugin, SudoEdit.vim also supports
reading and writing using the protocol sudo: So instead of using :SudoRead
/etc/fstab you can also use :e sudo:/etc/fstab (which does not provide
filename completion)

==============================================================================
2.2 SudoWrite                                                    *SudoWrite*

        :[range]SudoWrite[!] [file]

SudoWrite will write the given file using any of the configured methods for
superuser authentication. It basically does something like this: >

    :w !sudo tee >/dev/null file

If no filename is given, SudoWrite will try to write the current file name.
If the current buffer does not contain any file, it will abort.

You can specify a range to write just like |:w|. If no range is given, it will
write the whole file. If the bang argument is not given, the buffer will only
be written, if it was modified.

Again, you can use the protocol handler sudo: for writing.

==============================================================================
3. SudoEdit Configuration                               *SudoEdit-config*

By default SudoEdit will try to use sudo and if it is not found, it will try
to use su. Just because SudoEdit finds either sudo or su installed, does not
mean, that you can already use it. You might have to configure it and of
course you need to have the credentials for super-user access.

                                                                *g:sudoAuth*

The tool to use for authentication is can be changed by setting the variable
g:sudoAuth. If this variable exists, SudoEdit will first try to use the
specified tool before falling back to either sudo or su (in that order).

For example, you could use ssh to use as authentication tool by setting
g:sudoAuth in your .vimrc as follows: >

    let g:sudoAuth="ssh"
<
                                                               *g:sudoAuthArg*

The variable g:sudoAuthArg specifies how to use the given authentication tool.
You can specify additional parameters that will be used. You could for example
also define here which user to change to. By default, SudoEdit will try to
become the superuser e.g. root.

If you want to use ssh as authentication facility, you can set g:sudoAuthArg
as follows in your .vimrc: >

    let g:sudoAuthArg="root@localhost"

For su, you would use g:sudoAuthArg="-c", but you do not have to set it, the
plugin will automatically use -c if it detects, that su is used.

                                            *g:sudo_no_gui* *g:sudo_askpass*

If the plugin uses sudo for authenticating and the plugin finds any of
gnome-ssh-askpass, ksshaskpass or x11-ssh-askpass and a graphical Display
connection is possible, the plugin uses the first of the tools it finds to
display a graphical dialog, in which you can enter the password. If you like
to specify a different tool, you can set the g:sudo_askpass variable to
specify a different tool to use, e.g. >

    :let g:sudo_askpass='/usr/lib/openssh/gnome-ssh-askpass'

to make use of gnome-ssh-askpass for querying the password.

If you like to disable this, set the variable g:sudo_no_gui, e.g. >

    :let g:sudo_no_gui=1
<
							      *g:sudo_tee*

By default, the SudoEdit plugin uses the tee command to write your file (at
least on Unix and Mac). If you don't have the tee command available in your
path or you want to use a different tool, that is similar but called
differently, specify this option like this: >

    :let g:sudo_tee='/usr/bin/tee'

==============================================================================
3.1 SudoEdit on Windows                                          *SudoEdit-Win*

It should be possible to use SudoEdit on Windows using the runas command. The
plugin should by default try to detect when it runs under Windows and either
try to use runas or elevate. For this to work, those commands need to be in
your %PATH% and be executable. For runas, SudoEdit tries to simply run the
command like this: >

    runas /noprofile /user:Administrator "type file"

while elevate would simply use: >

    elevate "type file"

This has not yet been tested, but if you have successfully setup SudoEdit on
Windows, please let me know, so that the procedure can be properly documented.

Alternatively, it should be possible to setup SudoEdit to use the ShellRunAs,
sudowin or the Surun command and configuring the plugin using the |g:sudoAuth|
and |g:sudoAuthArg| variables.

If you need to use a different administrator account for Windows, I suggest
that you set the |g:sudoAuthArg| variable, e.g. setting: >

    :let g:sudoAuthArg = '/noprofile /user:\"AdminUser@MyDomain\"'

to let SudoEdit use the AdminUser within the domain MyDomain for administrator
access.

For further help on this topic see those links:

runas:
http://www.microsoft.com/resources/documentation/windows/xp/all/proddocs/en-us/runas.mspx

sudowin:
http://sourceforge.net/projects/sudowin/

elevate:
http://technet.microsoft.com/en-us/magazine/2007.06.utilityspotlight.aspx

ShellRunAs:
http://technet.microsoft.com/en-us/sysinternals/cc300361.aspx

Surun:
http://kay-bruns.de/wp/software/surun/

Alternatively, on recent Windows versions, you can use the builtin UAC system
and have a batch script automatically elevated, which will do the writing and
reading of the file. This method is rather experimental and might not work in
all cases. To make use of UAC set the g:sudoAuth variable to the string "uac":
>

    :let g:sudoAuth="uac"

==============================================================================
4. SudoEdit Debugging                                       *SudoEdit-debug*

You can debug this plugin and the shell code that will be executed by
setting: >

    let g:sudoDebug=1

This ensures, that debug messages will be appended to the |message-history|.

==============================================================================
5. SudoEdit F.A.Q.                                          *SudoEdit-faq*

1) This plugin isn't working, while executing the same commands on the
   shell works fine using sudo.

Make sure, that requiretty is not set. If it is set, you won't be able to use
sudo from within vim.

2) Vim is frozen!

Vim is probably waiting for the password but not redrawing correctly. You
should be able to enter your passphrase followed by Enter blindly and Vim
should respond again. In this case, try, if setting the g:sudoDebug variable
in your .vimrc helps >

    :let g:sudoDebug = 1

That should make the plugin output some more information and you should be
able to see the password prompt.

3) The plugin is still not working!

Write me an email (look in the first line for my mail address), append the
debug messages and tell me what exactly is not working. I will look into it
and if there is a bug fix this plugin.

4) The plugin does not create undo-files. What's wrong?

It is not directly possible to create undofiles in write-protected
directories, therefore, when your 'undodir' setting contains '.' (the
default), the plugin won't simply write the undofile. If you want undofiles to
work, set the 'undodir' option to a directory, that is writable.

5) Great work!

Write me an email (look in the first line for my mail address). And if you are
really happy, vote for the plugin and consider looking at my Amazon whishlist:
http://www.amazon.de/wishlist/2BKAHE8J7Z6UW

6) Plugin Feedback                                        *SudoEdit-feedback*

Feedback is always welcome. If you like the plugin, please rate it at the
vim-page:
http://www.vim.org/scripts/script.php?script_id=2709

You can also follow the development of the plugin at github:
http://github.com/chrisbra/SudoEdit.vim

Please don't hesitate to report any bugs to the maintainer, mentioned in the
third line of this document.

==============================================================================
6. SudoEdit History                                         *SudoEdit-history*
	0.21: (unreleased) "{{{1
	    - temporarily set shelltemp (issue 
	      https://github.com/chrisbra/SudoEdit.vim/issues/32, reported by
	      Fernando da Silva, thanks!)
	    - Do not trigger autocommands when writing temp files
	    - Make UAC actually work for Windows
	    - many small improvements for Windows
	0.20: Mar 27, 2014 "{{{1
	    - skip writing undo, if the buffer hasn't been written.
	    - document |g:sudo_tee| variable
	    - possibly wrong undofile was written (issue
	      https://github.com/chrisbra/SudoEdit.vim/issues/21, reported by
	      blueyed, thanks!)
        0.19: Aug 14, 2013 "{{{1
            - |SudoWrite| should always write if a filename has been given
              (issue #23, reported by Daniel Hahler, thanks!)
            - Better filename completion for |SudoWrite| and |SudoRead|
              commands (issue #20 reported by Daniel Hahler, thanks!)
            - Fix error in VimLeave autocommand (issue #22, reported by Daniel
              Hahler, thanks!)
            - reset 'shell' value (issue #24, reported by Raghavendra Prabhu,
              thanks!)
        0.18: Feb 16, 2013 "{{{1
            - expand() may return empty filenames (issue #17
              patch by Daniel Hahler, thanks!)
            - better exception handling (issue #19)
            - included sudo.cmd for better usage on Windows
            - enable sudo.cmd to use UAC optionally
        0.17: Aug 20, 2012 "{{{1
            - Guard against a vim without persistent_undo feature
            - fix variable typo
              (https://github.com/chrisbra/SudoEdit.vim/pull/16
              patch by NagatoPain, thanks!)
        0.16: May 17, 2012 "{{{1
            - Make the plugin usable on Windows |SudoEdit-Win|
        0.15: May 08, 2012 "{{{1
            - fix Syntax error (reported by Gary Johnson, thanks!)
        0.14: Apr 30, 2012 "{{{1
            - fix issue #15
              (https://github.com/chrisbra/SudoEdit.vim/issues/15
              reported by Lenin Lee, thanks!)
        0.13: Apr 28, 2012 "{{{1
            - in graphical Vim, display messages, so one knows, that one needs
              to enter the password (reported by Rob Shinn, thanks!)
            - Allow bang attribute to |SudoRead| and |SudoWrite|
            - Make use of graphical dialogs for sudo to read the passwords, if
              possible
            - Better debugging
            - Code cleanup
            - better filename completion with :SudoRead/SudoWrite (now also
              supports completing sudo: protocol handler)
        0.12: Jan 31, 2012 "{{{1
            - Avoid redraw when changing permissions of the undofile
            - Don't move cursor on Reading/Writing
              (issue https://github.com/chrisbra/SudoEdit.vim/issues/11,
              reported by Daniel Hahler, Thanks!)
            - Support for calling Netrw with another userid/password
              (issue https://github.com/chrisbra/SudoEdit.vim/issues/4,
              reported by Daniel Hahler, Thanks!)
            - Autocmds for Writing did not fire (issue
              https://github.com/chrisbra/SudoEdit.vim/issues/10, partly by
              Raghavendra D Prabhu, Thanks!)
            - Newly created files are not set 'nomodified' (issue
              https://github.com/chrisbra/SudoEdit.vim/issues/12, reported by
              Daniel Hahler, Thanks!)
            - Can't create undofiles in write-protected directories (issue
              https://github.com/chrisbra/SudoEdit.vim/issues/14, reported by
              Matias Kangasjärvelä, Thanks!)
        0.11: Dec 15, 2011 "{{{1
            -change owner of undofile to that of the edited super-user file,
             so vim will automatically load the undofile when opening that
             file the next time (reported by Sean Farley and blueyed, thanks!)
            -Only set the filename using :f when writing to another file
             (https://github.com/chrisbra/SudoEdit.vim/pull/8 and also
              https://github.com/chrisbra/SudoEdit.vim/issues/5 patch by
              Daniel Hahler, thanks!)
             -fix https://github.com/chrisbra/SudoEdit.vim/issues/6
             (fix permissions and path of the undofile, partly by Daniel
              Hahler, thanks!)
            -Don't reread the file and write undofiles for empty files
             (https://github.com/chrisbra/SudoEdit.vim/issues/7 reported by
             Daniel Hahler, thanks!)
        0.10: Nov 18, 2011 "{{{1
            -fix https://github.com/chrisbra/SudoEdit.vim/issues/1
             (exception "emptyfile" not caught, reported by Daniel Hahler,
             thanks!)
            -fix https://github.com/chrisbra/SudoEdit.vim/issues/2
             (Avoid W13 error, reported by Daniel Hahler, thanks!)
            -fix https://github.com/chrisbra/SudoEdit.vim/issues/3
             (Write undofiles, reported by Daniel Hahler, thanks!)
        0.8: Apr  20, 2010 "{{{1
            - Made plugin autoloadable so the code is only loaded,
              when necessary
        0.7: Oct  26, 2009 "{{{1
            - Support for reading/writing using sudo: protocol handler
            - Added Debugging capabilities
        0.6: July 14, 2009 "{{{1
            - Fix minor bug, that prevents setting the filename correctly
              when writing.
        0.5: July 08, 2009 "{{{1
            - Enables the plugin for |GetLatestVimScripts|
        0.4: July 08, 2009 "{{{1
            - First release
            - Added Documentation
        0.3: July 07, 2009 "{{{1
            - Internal version, added su support
            - Added configuration variables
        0.2: July 07, 2009 "{{{1
            - Internal version, Working sudo support
            - Created plugin
        0.1: July 07, 2009 "{{{1
            - Internal version, First working version, using simple commands

==============================================================================
Modeline: "{{{1
vim:tw=78:ts=8:ft=help:fdm=marker:fdl=0:norl
plugin/SudoEdit.vim	[[[1
84
" SudoEdit.vim - Use sudo/su for writing/reading files with Vim
" ---------------------------------------------------------------
" Version:  0.20
" Authors:  Christian Brabandt <cb@256bit.org>
" Last Change: Thu, 27 Mar 2014 23:19:50 +0100
" Script:  http://www.vim.org/scripts/script.php?script_id=2709 
" License: VIM License
" GetLatestVimScripts: 2709 20 :AutoInstall: SudoEdit.vim
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
  if a:A =~ '^s\%[udo]$'
    return [ "sudo:" ]
  endif
  let pat = matchstr(a:A, '^\(s\%[udo:]\)\?\zs.*')
  "let gpat = (pat[0] =~ '[./]' ? pat : './'.pat). '*'
  let gpat = (empty(pat) ? '*' : pat)
  if gpat !~# '[*?]$'
    " add star pattern for globbing
    let gpat .= '*'
  endif
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
autoload/sudo.cmd	[[[1
58
@echo off
cls

:: File to write to
set mode=%1
set myfile=%2
set newcontent=%3
set sudo=%4
shift
shift
shift
shift

if '%sudo%' == 'uac' goto CHECKPRIVILEGES

:: Use runas or something alike to elevate priviliges, but
:: first parse parameter for runas
:: Windows cmd.exe is very clumsy to use ;(
set params=%1
:LOOP
shift
if [%1]==[] goto AFTERLOOP
set params=%params% %1
goto LOOP

:AFTERLOOP

:: Use runas or so to elevate rights
echo.
echo ***************************************
echo Calling %sudo% for Privilege Escalation
echo ***************************************
if '%mode%' == 'write' (
    %sudo% %params% " %COMSPEC% /c copy /Y %newcontent% %myfile% "
) else (
    %sudo% %params% " %COMSPEC% /c copy /Y %myfile% %newcontent% "
)
exit /B

:: Use UAC to elevate rights, idea taken from:
:: http://stackoverflow.com/questions/7044985/how-can-i-auto-elevate-my-batch-file-so-that-it-requests-from-uac-admin-rights
:CHECKPRIVILEGES
set vbs="%temp%\GetPrivileges.vbs"

echo.
echo **************************************
echo Invoking UAC for Privilege Escalation 
echo **************************************

echo Set UAC = CreateObject^("Shell.Application"^) > %vbs%
if '%mode%' == 'write' (
    echo UAC.ShellExecute "%COMSPEC%", "/c copy /Y "%newcontent%" "%myfile%"", "", "runas", 1 >> %vbs%
) else (
    echo UAC.ShellExecute "%COMSPEC%", "/c copy /Y "%myfile%" "%newcontent%"", "", "runas", 1 >> %vbs%
)
:: Run VBS script and delete it afterwards
%vbs%
if exist %vbs% (del %vbs%)
