#!/bin/sh

echo "Please read INSTALL-CVS for instructions on how to build Emacs from CVS."

# Exit with failure, since people may have generic build scripts that
# try things like "autogen.sh && ./configure && make".
exit 1
