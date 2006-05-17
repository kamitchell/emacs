/* Copyright    Massachusetts Institute of Technology    1985	*/
/* Copyright (C) 2002, 2003, 2004, 2005,
                 2006 Free Software Foundation, Inc.  */

/*
Permission to use, copy, modify, distribute, and sell this software and its
documentation for any purpose is hereby granted without fee, provided that
the above copyright notice appear in all copies and that both that
copyright notice and this permission notice appear in supporting
documentation, and that the name of M.I.T. not be used in advertising or
publicity pertaining to distribution of the software without specific,
written prior permission.  M.I.T. makes no representations about the
suitability of this software for any purpose.  It is provided "as is"
without express or implied warranty.
*/

#include <X11/Xlib.h>
#include "X10.h"

/*
 * XDestroyAssocTable - Destroy (free the memory associated with)
 * an XAssocTable.
 */
XDestroyAssocTable(table)
	register XAssocTable *table;
{
	register int i;
	register XAssoc *bucket;
	register XAssoc *Entry, *entry_next;

	/* Free the buckets. */
	for (i = 0; i < table->size; i++) {
		bucket = &table->buckets[i];
		for (
	        	Entry = bucket->next;
			Entry != bucket;
			Entry = entry_next
		) {
		        entry_next = Entry->next;
			free((char *)Entry);
		}
	}

	/* Free the bucket array. */
	free((char *)table->buckets);

	/* Free the table. */
	free((char *)table);
}

/* arch-tag: a536bf02-8d63-45f2-8c1a-c7f9fd4da2cf
   (do not change this comment) */
