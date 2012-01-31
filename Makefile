SCRIPT=plugin/SudoEdit.vim autoload/SudoEdit.vim
DOC=doc/SudoEdit.txt
PLUGIN=SudoEdit
VERSION=$(shell sed -n '/Version:/{s/^.*\(\S\.\S\+\)$$/\1/;p}' $(SCRIPT))

.PHONY: $(PLUGIN).vmb clean

all: $(PLUGIN).vmb

version: $(PLUGIN) $(PLUGIN).vmb

clean:
	rm -rf *.vmb *.vba */*.orig *.~* .VimballRecord doc/tags
	find . -type f \( -name "*.vba" -o -name "*.orig" -o -name "*.~*" \
	-o -name ".VimballRecord" -o -name ".*.un~" -o -name "*.sw*" -o \
	-name tags -o -name "*.vmb" \) -delete

vimball:
	$(PLUGIN) $(PLUGIN).vmb

dist-clean: clean

install:
	vim -u NONE -N -c':so' -c':q!' ${PLUGIN}.vmb

release: $(PLUGIN) $(PLUGIN).vmb
	ln -f $(PLUGIN)-$(VERSION).vmb $(PLUGIN).vmb

uninstall:
	vim -u NONE -N -c':RmVimball ${PLUGIN}.vmb'

undo:
	for i in */*.orig; do mv -f "$$i" "$${i%.*}"; done

test:
	( cd test; ./test.sh )

SudoEdit.vmb:
	rm -f $(PLUGIN).vmb
	vim -N -c 'ru! vimballPlugin.vim' -c ':let g:vimball_home=getcwd()'  -c ':call append("0", ["autoload/SudoEdit.vim", "doc/SudoEdit.txt", "plugin/SudoEdit.vim"])' -c '$$d' -c ':%MkVimball ${PLUGIN}' -c':q!'
	vim -N -c 'ru! vimballPlugin.vim' -c ':so %' -c':q!' ${PLUGIN}.vmb

SudoEdit:
	perl -i.orig -pne 'if (/Version:/) {s/\.(\d*)/sprintf(".%d", 1+$$1)/e}' ${SCRIPT}
	perl -i -pne 'if (/GetLatestVimScripts:/) {s/(\d+)\s+:AutoInstall:/sprintf("%d :AutoInstall:", 1+$$1)/e}' ${SCRIPT}
	perl -i -pne 'if (/Last Change:/) {s/(:\s+).*\n/sprintf(": %s", `date -R`)/e}' ${SCRIPT}
	perl -i.orig -pne 'if (/Version:/) {s/\.(\d)+.*\n/sprintf(".%d %s", 1+$$1, `date -R`)/e}' ${DOC}

