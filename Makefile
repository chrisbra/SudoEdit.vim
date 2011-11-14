SCRIPT=plugin/SudoEdit.vim autoload/SudoEdit.vim
DOC=doc/SudoEdit.txt
PLUGIN=SudoEdit


all: $(PLUGIN) $(PLUGIN).vmb

clean:
	rm -rf *.vmb *.vba */*.orig *.~* .VimballRecord doc/tags

dist-clean: clean

install:
	vim -u NONE -N -c':so' -c':q!' ${PLUGIN}.vmb

uninstall:
	vim -u NONE -N -c':RmVimball ${PLUGIN}.vmb'

undo:
	for i in */*.orig; do mv -f "$$i" "$${i%.*}"; done

test:
	( cd test; ./test.sh )

SudoEdit.vmb:
	vim -N -c 'ru! vimballPlugin.vim' -c ':let g:vimball_home=getcwd()'  -c ':call append("0", ["autoload/SudoEdit.vim", "doc/SudoEdit.txt", "plugin/SudoEdit.vim"])' -c '$$d' -c ':%MkVimball ${PLUGIN}' -c':q!'
	vim -N -c 'ru! vimballPlugin.vim' -c ':so %' -c':q!' ${PLUGIN}.vmb

SudoEdit:
	rm -f ${PLUGIN}.vmb
	perl -i.orig -pne 'if (/Version:/) {s/\.(\d*)/sprintf(".%d", 1+$$1)/e}' ${SCRIPT}
	perl -i -pne 'if (/GetLatestVimScripts:/) {s/(\d+)\s+:AutoInstall:/sprintf("%d :AutoInstall:", 1+$$1)/e}' ${SCRIPT}
	perl -i -pne 'if (/Last Change:/) {s/(:\s+).*\n/sprintf(": %s", `date -R`)/e}' ${SCRIPT}
	perl -i.orig -pne 'if (/Version:/) {s/\.(\d)+.*\n/sprintf(".%d %s", 1+$$1, `date -R`)/e}' ${DOC}

