/* Resource definitions for GNU Emacs on the Macintosh when building
   under MPW.

   Copyright (C) 1999, 2000 Free Software Foundation, Inc.

This file is part of GNU Emacs.

GNU Emacs is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2, or (at your option)
any later version.

GNU Emacs is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with GNU Emacs; see the file COPYING.  If not, write to
the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
Boston, MA 02111-1307, USA.  */

/* Contributed by Andrew Choi (akochoi@mac.com).  */

#include "Types.r"
#include "CodeFragmentTypes.r"

resource 'SIZE' (-1) {
	reserved,
	acceptSuspendResumeEvents,
	reserved,
	canBackground,
	doesActivateOnFGSwitch,
	backgroundAndForeground,
	dontGetFrontClicks,
	ignoreAppDiedEvents,
	is32BitCompatible,
	isHighLevelEventAware,
	onlyLocalHLEvents,
	notStationeryAware,
	dontUseTextEditServices,
	reserved,
	reserved,
	reserved,
	33554432,
	16777216
};

#ifdef HAVE_CARBON
resource 'cfrg' (0) {
    {
	kPowerPCCFragArch, kIsCompleteCFrag, kNoVersionNum, kNoVersionNum,
	311296, /* 48K (default) + 256K (EXTRA_STACK_ALLOC in macterm.c) */
	kNoAppSubFolder,
	kApplicationCFrag, kDataForkCFragLocator, kZeroOffset, kCFragGoesToEOF,
	"",
    }
};
#endif
