/* font.h -- Interface definition for font handling.
   Copyright (C) 2006 Free Software Foundation, Inc.
   Copyright (C) 2006
     National Institute of Advanced Industrial Science and Technology (AIST)
     Registration Number H13PRO009

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
the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
Boston, MA 02110-1301, USA.  */

#ifndef EMACS_FONT_H
#define EMACS_FONT_H

#include "ccl.h"

/* We have three types of Lisp objects related to font.

   FONT-SPEC

	Vector (length FONT_SPEC_MAX) of font properties.  Some
	properties can be left unspecified (i.e. nil).  Emacs asks
	font-drivers to find a font by FONT-SPEC.  A fontset entry
	specifies requisite properties whereas a face specifies just
	preferable properties.  This object is fully modifiable by
	Lisp.

   FONT-ENTITY

	Vector (length FONT_ENTITY_MAX) of fully specified font
	properties that a font-driver returns upon a request of
	FONT-SPEC.

	Note: Only the method `list' of a font-driver can create this
	object, and should never be modified by Lisp.  In that sense,
	it may be cleaner to implement it as a Lisp object of a new
	type (e.g. struct Lisp_Font).

   FONT-OBJECT

	Lisp object of type Lisp_Misc_Save_Value encapsulating a
	pointer to "struct font".  This corresponds to an opened font.

	Note: The note for FONT-ENTITY also applies to this.
*/


struct font_driver;
struct font;

/* An enumerator for each font property.  This is used as an index to
   the vector of FONT-SPEC and FONT-ENTITY.

   Note: The order is important and should not be changed.  */

enum font_property_index
  {
    /* FONT-TYPE is a symbol indicating a font backend; currently `x',
       `xft', `ftx', `freetype' are available.  For windows, we need
       `bdf' and `windows'.  For Mac OS X, we need `atm'.  */
    FONT_TYPE_INDEX,

    /* FONT-FOUNDRY is a foundry name (symbol).  */
    FONT_FOUNDRY_INDEX,

    /* FONT-FAMILY is a family name (symbol).  */
    FONT_FAMILY_INDEX,

    /* FONT-ADSTYLE is an additional style name (symbol).  */
    FONT_ADSTYLE_INDEX,

    /* FONT-REGISTRY is a combination of a charset-registry and
       charset0encoding name (symbol).  */
    FONT_REGISTRY_INDEX,

    /* FONT-WEIGHT is a numeric value of weight (e.g. medium, bold) of
       the font.  The value is what defined by FC_WEIGHT_* in
       fontconfig. */
    FONT_WEIGHT_INDEX,

    /* FONT-SLANT is a numeric value of slant (e.g. r, i, o) of the
       font.  The value is what defined by FC_SLANT_* in
       fontconfig plus 100. */
    FONT_SLANT_INDEX,

    /* FONT-WIDTH is a numeric value of setwidth (e.g. normal,
       condensed) of the font.  The value is what defined by
       FC_WIDTH_* in fontconfig. */
    FONT_WIDTH_INDEX,

    /* FONT-SIZE is a size of the font.  If integer, it is a pixel
       size.  For a font-spec, the value can be float specifying a
       point size.  For a font-entity, the value can be zero meaning
       that the font is scalable.  */
    FONT_SIZE_INDEX,

    /* In a font-spec, the value is an alist of extra information of a
       font such as name, OpenType features, and language coverage.
       In a font-entity, the value is an extra infomation for
       identifying a font (font-driver dependent).  */
    FONT_EXTRA_INDEX,		/* alist		alist */

    /* This value is the length of font-spec vector.  */
    FONT_SPEC_MAX,

    /* The followings are used only for a font-entity.  */

    /* Frame on which the font is found.  The value is nil if the font
       can be opend on any frame.  */
    FONT_FRAME_INDEX = FONT_SPEC_MAX,

    /* List of font-objects opened from the font-entity.  */
    FONT_OBJLIST_INDEX,

    /* This value is the length of font-entity vector.  */
    FONT_ENTITY_MAX
  };

extern Lisp_Object QCspacing, QCdpi, QCscalable, QCotf, QClanguage, QCscript;

/* Important character set symbols.  */
extern Lisp_Object Qiso8859_1, Qiso10646_1, Qunicode_bmp, Qunicode_sip;

extern Lisp_Object null_string;
extern Lisp_Object null_vector;

/* Structure for an opened font.  We can safely cast this structure to
   "struct font_info".  */

struct font
{
  struct font_info font;

  /* From which font-entity the font is opened.  */
  Lisp_Object entity;

  /* By which pixel size the font is opened.  */
  int pixel_size;

  /* Font-driver for the font.  */
  struct font_driver *driver;

  /* Symbol of font font; x, ttf, pcf, etc,   */
  Lisp_Object format;

  /* File name of the font, or NULL if the font is not associated with
     a file.  */
  char *file_name;

  /* Charset to encode a character code into a glyph code of the font.
     -1 means that the font doesn't require this information to encode
     a character.  */
  int encoding_charset;

  /* Charset to check if a character code is supported by the font.
     -1 means that the contents of the font must be looked up to
     determine it.  */
  int repertory_charset;

  /* Minimum glyph width (in pixels).  */
  int min_width;

  /* Ascent and descent of the font (in pixels).  */
  int ascent, descent;

  /* 1 iff the font is scalable.  */
  int scalable;

  /* There will be more to this structure, but they are private to a
     font-driver.  */
};

enum font_spacing
  {
    FONT_SPACING_PROPORTIONAL = 0,
    FONT_SPACING_DUAL = 90,
    FONT_SPACING_MONO = 100,
    FONT_SPACING_CHARCELL = 110
  };

struct font_metrics
{
  short lbearing, rbearing, width, ascent, descent;
};

struct font_bitmap
{
  int rows;
  int width;
  int pitch;
  unsigned char *buffer;
  int left;
  int top;
  int advance;
  void *extra;
};

/* Predicates to check various font-related objects.  */

#define FONTP(x)	\
  (VECTORP (x) && (ASIZE (x) == FONT_SPEC_MAX || ASIZE (x) == FONT_ENTITY_MAX))
#define FONT_SPEC_P(x)	\
  (VECTORP (x) && ASIZE (x) == FONT_SPEC_MAX)
#define FONT_ENTITY_P(x)	\
  (VECTORP (x) && ASIZE (x) == FONT_ENTITY_MAX)
#define FONT_OBJECT_P(x)	\
  (XTYPE (x) == Lisp_Misc && XMISCTYPE (x) == Lisp_Misc_Save_Value)


/* Check macros for various font-related objects.  */

#define CHECK_FONT(x)	\
  do { if (! FONTP (x)) x = wrong_type_argument (Qfont, x); } while (0)
#define CHECK_FONT_SPEC(x)	\
  do { if (! FONT_SPEC_P (x)) x = wrong_type_argument (Qfont, x); } while (0)
#define CHECK_FONT_ENTITY(x)	\
  do { if (! FONT_ENTITY_P (x)) x = wrong_type_argument (Qfont, x); } while (0)
#define CHECK_FONT_OBJECT(x)	\
  do { if (! FONT_OBJECT_P (x)) x = wrong_type_argument (Qfont, x); } while (0)

#define CHECK_FONT_GET_OBJECT(x, font)					\
  do {									\
    if (! FONT_OBJECT_P (x)) x = wrong_type_argument (Qfont, x);	\
    if (! XSAVE_VALUE (x)->pointer) error ("Font already closed");	\
    font = XSAVE_VALUE (x)->pointer;					\
  } while (0)

/* Ignore the difference of font pixel sizes less than or equal to
   this value.  */
#define FONT_PIXEL_SIZE_QUANTUM 1

struct face;
struct composition;

/* Macros for lispy glyph-string.  */
#define LGSTRING_FONT(lgs) AREF (AREF ((lgs), 0), 0)
#define LGSTRING_LBEARING(lgs) AREF (AREF ((lgs), 0), 1)
#define LGSTRING_RBEARING(lgs) AREF (AREF ((lgs), 0), 2)
#define LGSTRING_WIDTH(lgs) AREF (AREF ((lgs), 0), 3)
#define LGSTRING_ASCENT(lgs) AREF (AREF ((lgs), 0), 4)
#define LGSTRING_DESCENT(lgs) AREF (AREF ((lgs), 0), 5)
#define LGSTRING_SET_FONT(lgs, val) ASET (AREF ((lgs), 0), 0, (val))
#define LGSTRING_SET_LBEARING(lgs, val) ASET (AREF ((lgs), 0), 1, (val))
#define LGSTRING_SET_RBEARING(lgs, val)	ASET (AREF ((lgs), 0), 2, (val))
#define LGSTRING_SET_WIDTH(lgs, val) ASET (AREF ((lgs), 0), 3, (val))
#define LGSTRING_SET_ASCENT(lgs, val) ASET (AREF ((lgs), 0), 4, (val))
#define LGSTRING_SET_DESCENT(lgs, val) ASET (AREF ((lgs), 0), 5, (val))

#define LGSTRING_LENGTH(lgs) (ASIZE ((lgs)) - 1)
#define LGSTRING_GLYPH(lgs, idx) AREF ((lgs), (idx) + 1)

#define LGLYPH_FROM(g) AREF ((g), 0)
#define LGLYPH_TO(g) AREF ((g), 1)
#define LGLYPH_CHAR(g) AREF ((g), 2)
#define LGLYPH_CODE(g) AREF ((g), 3)
#define LGLYPH_WIDTH(g) AREF ((g), 4)
#define LGLYPH_ADJUSTMENT(g) AREF ((g), 5)
#define LGLYPH_SET_FROM(g, val) ASET ((g), 0, (val))
#define LGLYPH_SET_TO(g, val) ASET ((g), 1, (val))
#define LGLYPH_SET_CHAR(g, val) ASET ((g), 2, (val))
#define LGLYPH_SET_CODE(g, val) ASET ((g), 3, (val))
#define LGLYPH_SET_WIDTH(g, val) ASET ((g), 4, (val))
#define LGLYPH_SET_ADJUSTMENT(g, val) ASET ((g), 5, (val))

#define LGLYPH_XOFF(g) (VECTORP (LGLYPH_ADJUSTMENT (g)) \
			? XINT (AREF (LGLYPH_ADJUSTMENT (g), 0)) : 0)
#define LGLYPH_YOFF(g) (VECTORP (LGLYPH_ADJUSTMENT (g)) \
			? XINT (AREF (LGLYPH_ADJUSTMENT (g), 1)) : 0)
#define LGLYPH_WADJUST(g) (VECTORP (LGLYPH_ADJUSTMENT (g)) \
			   ? XINT (AREF (LGLYPH_ADJUSTMENT (g), 2)) : 0)

#define FONT_INVALID_CODE 0xFFFFFFFF

/* Font driver.  Members specified as "optional" can be NULL.  */

struct font_driver
{
  /* Symbol indicating the type of the font-driver.  */
  Lisp_Object type;

  /* Return a cache of font-entities on FRAME.  The cache must be a
     cons whose cdr part is the actual cache area.  */
  Lisp_Object (*get_cache) P_ ((Lisp_Object frame));

  /* List fonts exactly matching with FONT_SPEC on FRAME.  The value
     is a vector of font-entities.  This is the sole API that
     allocates font-entities.  */
  Lisp_Object (*list) P_ ((Lisp_Object frame, Lisp_Object font_spec));

  /* Return a font entity most closely maching with FONT_SPEC on
     FRAME.  The closeness is detemined by the font backend, thus
     `face-font-selection-order' is ignored here.  */
  Lisp_Object (*match) P_ ((Lisp_Object frame, Lisp_Object font_spec));

  /* Optional.
     List available families.  The value is a list of family names
     (symbols).  */
  Lisp_Object (*list_family) P_ ((Lisp_Object frame));

  /* Optional (if FONT_EXTRA_INDEX is not Lisp_Save_Value).
     Free FONT_EXTRA_INDEX field of FONT_ENTITY.  */
  void (*free_entity) P_ ((Lisp_Object font_entity));

  /* Open a font specified by FONT_ENTITY on frame F.  If the font is
     scalable, open it with PIXEL_SIZE.  */
  struct font *(*open) P_ ((FRAME_PTR f, Lisp_Object font_entity,
			    int pixel_size));

  /* Close FONT on frame F.  */
  void (*close) P_ ((FRAME_PTR f, struct font *font));

  /* Optional (if FACE->extra is not used).
     Prepare FACE for displaying characters by FONT on frame F by
     storing some data in FACE->extra.  If successful, return 0.
     Otherwise, return -1.  */
  int (*prepare_face) P_ ((FRAME_PTR f, struct face *face));

  /* Optional.
     Done FACE for displaying characters by FACE->font on frame F.  */
  void (*done_face) P_ ((FRAME_PTR f, struct face *face));

  /* Optional.
     If FONT_ENTITY has a glyph for character C (Unicode code point),
     return 1.  If not, return 0.  If a font must be opened to check
     it, return -1.  */
  int (*has_char) P_ ((Lisp_Object entity, int c));

  /* Return a glyph code of FONT for characer C (Unicode code point).
     If FONT doesn't have such a glyph, return FONT_INVALID_CODE.  */
  unsigned (*encode_char) P_ ((struct font *font, int c));

  /* Perform the size computation of glyphs of FONT and fillin members
     of METRICS.  The glyphs are specified by their glyph codes in
     CODE (length NGLYPHS).  */
  int (*text_extents) P_ ((struct font *font,
			   unsigned *code, int nglyphs,
			   struct font_metrics *metrics));

  /* Optional.
     Draw glyphs between FROM and TO of S->char2b at (X Y) pixel
     position of frame F with S->FACE and S->GC.  If WITH_BACKGROUND
     is nonzero, fill the background in advance.  It is assured that
     WITH_BACKGROUND is zero when (FROM > 0 || TO < S->nchars).  */
  int (*draw) P_ ((struct glyph_string *s, int from, int to,
		   int x, int y, int with_background));

  /* Optional.
     Store bitmap data for glyph-code CODE of FONT in BITMAP.  It is
     intended that this method is callled from the other font-driver
     for actual drawing.  */
  int (*get_bitmap) P_ ((struct font *font, unsigned code,
			 struct font_bitmap *bitmap,
			 int bits_per_pixel));

  /* Optional.
     Free bitmap data in BITMAP.  */
  void (*free_bitmap) P_ ((struct font *font, struct font_bitmap *bitmap));

  /* Optional.
     Return an outline data for glyph-code CODE of FONT.  The format
     of the outline data depends on the font-driver.  */
  void *(*get_outline) P_ ((struct font *font, unsigned code));

  /* Optional.
     Free OUTLINE (that is obtained by the above method).  */
  void (*free_outline) P_ ((struct font *font, void *outline));

  /* Optional.
     Get coordinates of the INDEXth anchor point of the glyph whose
     code is CODE.  Store the coordinates in *X and *Y.  Return 0 if
     the operations was successfull.  Otherwise return -1.  */
  int (*anchor_point) P_ ((struct font *font, unsigned code, int index,
			   int *x, int *y));

  /* Optional.
     Return a list describing which scripts/languages FONT
     supports by which GSUB/GPOS features of OpenType tables.  */
  Lisp_Object (*otf_capability) P_ ((struct font *font));

  /* Optional.
     Apply FONT's OTF-FEATURES to the glyph string.

     FEATURES specifies which OTF features to apply in this format:
	(SCRIPT LANGSYS GSUB-FEATURE GPOS-FEATURE)
     See the documentation of `font-drive-otf' for the detail.

     This method applies the specified features to the codes in the
     elements of GSTRING-IN (between FROMth and TOth).  The output
     codes are stored in GSTRING-OUT at the IDXth element and the
     following elements.

     Return the number of output codes.  If none of the features are
     applicable to the input data, return 0.  If GSTRING-OUT is too
     short, return -1.  */
  int (*otf_drive) P_ ((struct font *font, Lisp_Object features,
		       Lisp_Object gstring_in, int from, int to,
		       Lisp_Object gstring_out, int idx, int alternate_subst));
};


struct font_driver_list
{
  /* 1 iff this driver is currently used.  */
  int on;
  struct font_driver *driver;
  struct font_driver_list *next;
};

extern int enable_font_backend;

EXFUN (Ffont_spec, MANY);
EXFUN (Flist_fonts, 4);
EXFUN (Fclear_font_cache, 0);
EXFUN (Ffont_xlfd_name, 1);

extern Lisp_Object font_symbolic_weight P_ ((Lisp_Object font));
extern Lisp_Object font_symbolic_slant P_ ((Lisp_Object font));
extern Lisp_Object font_symbolic_width P_ ((Lisp_Object font));

extern int font_match_p P_ ((Lisp_Object spec, Lisp_Object entity));

extern Lisp_Object font_find_object P_ ((struct font *font));
extern Lisp_Object font_get_name P_ ((Lisp_Object font_object));
extern Lisp_Object font_get_spec P_ ((Lisp_Object font_object));
extern Lisp_Object font_get_frame P_ ((Lisp_Object font_object));
extern int font_has_char P_ ((FRAME_PTR, Lisp_Object, int));
extern unsigned font_encode_char P_ ((Lisp_Object, int));

extern int font_set_lface_from_name P_ ((FRAME_PTR f,
					 Lisp_Object lface,
					 Lisp_Object fontname,
					 int force_p, int may_fail_p));
extern Lisp_Object font_find_for_lface P_ ((FRAME_PTR f, Lisp_Object *lface,
					    Lisp_Object spec));
extern Lisp_Object font_open_for_lface P_ ((FRAME_PTR f, Lisp_Object entity,
					    Lisp_Object *lface,
					    Lisp_Object spec));
extern void font_load_for_face P_ ((FRAME_PTR f, struct face *face));
extern void font_prepare_for_face P_ ((FRAME_PTR f, struct face *face));
extern Lisp_Object font_open_by_name P_ ((FRAME_PTR f, char *name));
extern void font_close_object (FRAME_PTR f, Lisp_Object font_object);

extern Lisp_Object intern_downcase P_ ((char *str, int len));
extern void font_update_sort_order P_ ((int *order));

extern void font_merge_old_spec P_ ((Lisp_Object name, Lisp_Object family,
				     Lisp_Object registry, Lisp_Object spec));


extern int font_parse_xlfd P_ ((char *name, Lisp_Object font));
extern int font_unparse_xlfd P_ ((Lisp_Object font, int pixel_size,
				  char *name, int bytes));
extern int font_parse_fcname P_ ((char *name, Lisp_Object font));
extern int font_unparse_fcname P_ ((Lisp_Object font, int pixel_size,
				  char *name, int bytes));
extern void register_font_driver P_ ((struct font_driver *driver, FRAME_PTR f));
extern void free_font_driver_list P_ ((FRAME_PTR f));
extern Lisp_Object font_update_drivers P_ ((FRAME_PTR f, Lisp_Object list));
extern Lisp_Object font_at P_ ((int c, EMACS_INT pos, struct face *face,
				struct window *w, Lisp_Object object));

extern struct font *font_prepare_composition P_ ((struct composition *cmp));

extern Lisp_Object font_put_extra P_ ((Lisp_Object font, Lisp_Object prop,
                                       Lisp_Object val));

#ifdef HAVE_LIBOTF
/* This can be used as `otf_capability' method of a font-driver.  */
extern Lisp_Object font_otf_capability P_ ((struct font *font));
/* This can be used as `otf_drive' method of a font-driver.  */
extern int font_drive_otf P_ ((struct font *font, Lisp_Object otf_features,
			       Lisp_Object gstring_in, int from, int to,
			       Lisp_Object gstring_out, int idx,
			       int alternate_subst));
#endif	/* HAVE_LIBOTF */

#ifdef HAVE_FREETYPE
extern struct font_driver ftfont_driver;
#endif	/* HAVE_FREETYPE */
#ifdef HAVE_X_WINDOWS
extern struct font_driver xfont_driver;
extern struct font_driver ftxfont_driver;
#ifdef HAVE_XFT
extern struct font_driver xftfont_driver;
#endif	/* HAVE_XFT */
#endif	/* HAVE_X_WINDOWS */
#ifdef WINDOWSNT
extern struct font_driver w32font_driver;
#endif	/* WINDOWSNT */
#ifdef MAC_OS
extern struct font_driver atmfont_driver;
#endif	/* MAC_OS */

#endif	/* not EMACS_FONT_H */

/* arch-tag: 3b7260c3-5bec-4d6b-a0db-95c1b431b1a2
   (do not change this comment) */
