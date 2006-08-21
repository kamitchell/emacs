/* xftfont.c -- XFT font driver.
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

#include <config.h>
#include <stdio.h>
#include <X11/Xlib.h>
#include <X11/Xft/Xft.h>

#include "lisp.h"
#include "dispextern.h"
#include "xterm.h"
#include "frame.h"
#include "blockinput.h"
#include "character.h"
#include "charset.h"
#include "fontset.h"
#include "font.h"

/* Xft font driver.  */

static Lisp_Object Qxft;

/* The actual structure for Xft font that can be casted to struct
   font.  */

struct xftfont_info
{
  struct font font;
  Display *display;
  int screen;
  XftFont *xftfont;
  FT_Face ft_face;		/* set to XftLockFace (xftfont) */
};

/* Structure pointed by (struct face *)->extra  */

struct xftface_info
{
  XftColor xft_fg;		/* color for face->foreground */
  XftColor xft_bg;		/* color for face->background */
  XftDraw *xft_draw;
};

static void xftfont_get_colors P_ ((FRAME_PTR, struct face *, GC gc,
				    struct xftface_info *,
				    XftColor *fg, XftColor *bg));
static Font xftfont_default_fid P_ ((FRAME_PTR));


/* Setup foreground and background colors of GC into FG and BG.  If
   XFTFACE_INFO is not NULL, reuse the colors in it if possible.  BG
   may be NULL.  */

static void
xftfont_get_colors (f, face, gc, xftface_info, fg, bg)
     FRAME_PTR f;
     struct face *face;
     GC gc;
     struct xftface_info *xftface_info;
     XftColor *fg, *bg;
{
  if (xftface_info && face->gc == gc)
    {
      *fg = xftface_info->xft_fg;
      if (bg)
	*bg = xftface_info->xft_bg;
    }
  else
    {
      XGCValues xgcv;
      int fg_done = 0, bg_done = 0;

      BLOCK_INPUT;
      XGetGCValues (FRAME_X_DISPLAY (f), gc,
		    GCForeground | GCBackground, &xgcv);
      if (xftface_info)
	{
	  if (xgcv.foreground == face->foreground)
	    *fg = xftface_info->xft_fg, fg_done = 1;
	  else if (xgcv.foreground == face->background)
	    *fg = xftface_info->xft_bg, fg_done = 1;
	  if (! bg)
	    bg_done = 1;
	  else if (xgcv.background == face->background)
	    *bg = xftface_info->xft_bg, bg_done = 1;
	  else if (xgcv.background == face->foreground)
	    *bg = xftface_info->xft_fg, bg_done = 1;
	}

      if (fg_done + bg_done < 2)
	{
	  XColor colors[2];

	  colors[0].pixel = fg->pixel = xgcv.foreground;
	  if (bg)
	    colors[1].pixel = bg->pixel = xgcv.background;
	  XQueryColors (FRAME_X_DISPLAY (f), FRAME_X_COLORMAP (f), colors,
			bg ? 2 : 1);
	  fg->color.alpha = 0xFFFF;
	  fg->color.red = colors[0].red;
	  fg->color.green = colors[0].green;
	  fg->color.blue = colors[0].blue;
	  if (bg)
	    {
	      bg->color.alpha = 0xFFFF;
	      bg->color.red = colors[1].red;
	      bg->color.green = colors[1].green;
	      bg->color.blue = colors[1].blue;
	    }
	}
      UNBLOCK_INPUT;
    }
}

/* Return the default Font ID on frame F.  The Returned Font ID is
   stored in the GC of the frame F, but the font is never used.  So,
   any ID is ok as long as it is valid.  */

static Font
xftfont_default_fid (f)
     FRAME_PTR f;
{
  static int fid_known;
  static Font fid;

  if (! fid_known)
    {
      fid = XLoadFont (FRAME_X_DISPLAY (f), "fixed");
      if (! fid)
	{
	  fid = XLoadFont (FRAME_X_DISPLAY (f), "*");
	  if (! fid)
	    abort ();
	}
      fid_known = 1;
    }
  return fid;
}


static Lisp_Object xftfont_list P_ ((Lisp_Object, Lisp_Object));
static Lisp_Object xftfont_match P_ ((Lisp_Object, Lisp_Object));
static struct font *xftfont_open P_ ((FRAME_PTR, Lisp_Object, int));
static void xftfont_close P_ ((FRAME_PTR, struct font *));
static int xftfont_prepare_face P_ ((FRAME_PTR, struct face *));
static void xftfont_done_face P_ ((FRAME_PTR, struct face *));
static unsigned xftfont_encode_char P_ ((struct font *, int));
static int xftfont_text_extents P_ ((struct font *, unsigned *, int,
				     struct font_metrics *));
static int xftfont_draw P_ ((struct glyph_string *, int, int, int, int, int));

static int xftfont_anchor_point P_ ((struct font *, unsigned, int,
				     int *, int *));

struct font_driver xftfont_driver;

static Lisp_Object
xftfont_list (frame, spec)
     Lisp_Object frame;
     Lisp_Object spec;
{
  Lisp_Object val = ftfont_driver.list (frame, spec);
  int i;
  
  if (! NILP (val))
    for (i = 0; i < ASIZE (val); i++)
      ASET (AREF (val, i), FONT_TYPE_INDEX, Qxft);
  return val;
}

static Lisp_Object
xftfont_match (frame, spec)
     Lisp_Object frame;
     Lisp_Object spec;
{
  Lisp_Object entity = ftfont_driver.match (frame, spec);

  if (VECTORP (entity))
    ASET (entity, FONT_TYPE_INDEX, Qxft);
  return entity;
}

static FcChar8 ascii_printable[95];

static struct font *
xftfont_open (f, entity, pixel_size)
     FRAME_PTR f;
     Lisp_Object entity;
     int pixel_size;
{
  Display_Info *dpyinfo = FRAME_X_DISPLAY_INFO (f);
  Display *display = FRAME_X_DISPLAY (f);
  Lisp_Object val;
  FcPattern *pattern, *pat = NULL;
  FcChar8 *file;
  struct xftfont_info *xftfont_info = NULL;
  XFontStruct *xfont = NULL;
  struct font *font;
  double size = 0;
  XftFont *xftfont = NULL;
  int spacing;
  char *name;
  int len;

  val = AREF (entity, FONT_EXTRA_INDEX);
  if (XTYPE (val) != Lisp_Misc
      || XMISCTYPE (val) != Lisp_Misc_Save_Value)
    return NULL;
  pattern = XSAVE_VALUE (val)->pointer;
  if (FcPatternGetString (pattern, FC_FILE, 0, &file) != FcResultMatch)
    return NULL;

  size = XINT (AREF (entity, FONT_SIZE_INDEX));
  if (size == 0)
    size = pixel_size;

  pat = FcPatternCreate ();
  FcPatternAddString (pat, FC_FILE, file);
  FcPatternAddDouble (pat, FC_PIXEL_SIZE, pixel_size);
  FcPatternAddBool (pat, FC_ANTIALIAS, FcTrue);

  BLOCK_INPUT;
  XftDefaultSubstitute (display, FRAME_X_SCREEN_NUMBER (f), pat);
  xftfont = XftFontOpenPattern (display, pat);
  /* We should not destroy PAT here because it is kept in XFTFONT and
     destroyed automatically when XFTFONT is closed.  */
  if (! xftfont)
    goto err;

  xftfont_info = malloc (sizeof (struct xftfont_info));
  if (! xftfont_info)
    goto err;
  xfont = malloc (sizeof (XFontStruct));
  if (! xfont)
    goto err;
  xftfont_info->display = display;
  xftfont_info->screen = FRAME_X_SCREEN_NUMBER (f);
  xftfont_info->xftfont = xftfont;
  xftfont_info->ft_face = XftLockFace (xftfont);

  font = (struct font *) xftfont_info;
  font->entity = entity;
  font->pixel_size = size;
  font->driver = &xftfont_driver;
  len = 96;
  name = malloc (len);
  while (name && font_unparse_fcname (entity, pixel_size, name, len) < 0)
    {
      char *new = realloc (name, len += 32);

      if (! new)
	free (name);
      name = new;
    }
  if (! name)
    goto err;
  font->font.full_name = font->font.name = name;
  font->file_name = (char *) file;
  font->font.size = xftfont->max_advance_width;
  font->font.charset = font->encoding_charset = font->repertory_charset = -1;
  font->ascent = xftfont->ascent;
  font->descent = xftfont->descent;
  font->font.height = xftfont->ascent + xftfont->descent;

  if (FcPatternGetInteger (xftfont->pattern, FC_SPACING, 0, &spacing)
      != FcResultMatch)
    spacing = FC_PROPORTIONAL;
  if (spacing != FC_PROPORTIONAL)
    font->font.average_width = font->font.space_width
      = xftfont->max_advance_width;
  else
    {
      XGlyphInfo extents;

      if (! ascii_printable[0])
	{
	  int i;
	  for (i = 0; i < 95; i++)
	    ascii_printable[i] = ' ' + i;
	}
      XftTextExtents8 (display, xftfont, ascii_printable, 1, &extents);
      font->font.space_width = extents.xOff;
      if (font->font.space_width <= 0)
	/* dirty workaround */
	font->font.space_width = pixel_size;	
      XftTextExtents8 (display, xftfont, ascii_printable + 1, 94, &extents);
      font->font.average_width = (font->font.space_width + extents.xOff) / 95;
    }
  UNBLOCK_INPUT;

  /* Unfortunately Xft doesn't provide a way to get minimum char
     width.  So, we use space_width instead.  */
  font->min_width = font->font.space_width;

  font->font.baseline_offset = 0;
  font->font.relative_compose = 0;
  font->font.default_ascent = 0;
  font->font.vertical_centering = 0;

  /* Setup pseudo XFontStruct */
  xfont->fid = xftfont_default_fid (f);
  xfont->ascent = xftfont->ascent;
  xfont->descent = xftfont->descent;
  xfont->max_bounds.descent = xftfont->descent;
  xfont->max_bounds.width = xftfont->max_advance_width;
  xfont->min_bounds.width = font->font.space_width;
  font->font.font = xfont;

  dpyinfo->n_fonts++;

  /* Set global flag fonts_changed_p to non-zero if the font loaded
     has a character with a smaller width than any other character
     before, or if the font loaded has a smaller height than any other
     font loaded before.  If this happens, it will make a glyph matrix
     reallocation necessary.  */
  if (dpyinfo->n_fonts == 1)
    {
      dpyinfo->smallest_font_height = font->font.height;
      dpyinfo->smallest_char_width = font->min_width;
      fonts_changed_p = 1;
    }
  else
    {
      if (dpyinfo->smallest_font_height > font->font.height)
	dpyinfo->smallest_font_height = font->font.height,
	  fonts_changed_p |= 1;
      if (dpyinfo->smallest_char_width > font->min_width)
	dpyinfo->smallest_char_width = font->min_width,
	  fonts_changed_p |= 1;
    }

  return font;

 err:
  if (xftfont) XftFontClose (display, xftfont);
  UNBLOCK_INPUT;
  if (xftfont_info) free (xftfont_info);
  if (xfont) free (xfont);
  return NULL;
}

static void
xftfont_close (f, font)
     FRAME_PTR f;
     struct font *font;
{
  struct xftfont_info *xftfont_info = (struct xftfont_info *) font;

  XftUnlockFace (xftfont_info->xftfont);
  XftFontClose (xftfont_info->display, xftfont_info->xftfont);
  if (font->font.name)
    free (font->font.name);
  free (font);
  FRAME_X_DISPLAY_INFO (f)->n_fonts--;
}

static int
xftfont_prepare_face (f, face)
     FRAME_PTR f;
     struct face *face;
{
  struct xftface_info *xftface_info;

#if 0
  /* This doesn't work if face->ascii_face doesn't use an Xft font. */
  if (face != face->ascii_face)
    {
      face->extra = face->ascii_face->extra;
      return 0;
    }
#endif

  xftface_info = malloc (sizeof (struct xftface_info));
  if (! xftface_info)
    return -1;

  BLOCK_INPUT;
  xftface_info->xft_draw = XftDrawCreate (FRAME_X_DISPLAY (f),
					  FRAME_X_WINDOW (f),
					  FRAME_X_VISUAL (f),
					  FRAME_X_COLORMAP (f));
  xftfont_get_colors (f, face, face->gc, NULL,
		      &xftface_info->xft_fg, &xftface_info->xft_bg);
  UNBLOCK_INPUT;

  face->extra = xftface_info;
  return 0;
}

static void
xftfont_done_face (f, face)
     FRAME_PTR f;
     struct face *face;
{
  struct xftface_info *xftface_info;
  
#if 0
  /* This doesn't work if face->ascii_face doesn't use an Xft font. */
  if (face != face->ascii_face
      || ! face->extra)
    return;
#endif

  xftface_info = (struct xftface_info *) face->extra;
  if (xftface_info)
    {
      BLOCK_INPUT;
      XftDrawDestroy (xftface_info->xft_draw);
      UNBLOCK_INPUT;
      free (xftface_info);
    }
  face->extra = NULL;
}

static unsigned
xftfont_encode_char (font, c)
     struct font *font;
     int c;
{
  struct xftfont_info *xftfont_info = (struct xftfont_info *) font;
  unsigned code = XftCharIndex (xftfont_info->display, xftfont_info->xftfont,
				(FcChar32) c);
  
  return (code ? code : 0xFFFFFFFF);
}

static int
xftfont_text_extents (font, code, nglyphs, metrics)
     struct font *font;
     unsigned *code;
     int nglyphs;
     struct font_metrics *metrics;
{
  struct xftfont_info *xftfont_info = (struct xftfont_info *) font;
  XGlyphInfo extents;

  BLOCK_INPUT;
  XftGlyphExtents (xftfont_info->display, xftfont_info->xftfont, code, nglyphs,
		   &extents);
  UNBLOCK_INPUT;
  if (metrics)
    {
      metrics->lbearing = - extents.x;
      metrics->rbearing = - extents.x + extents.width;
      metrics->width = extents.xOff;
      metrics->ascent = extents.y;
      metrics->descent = extents.y - extents.height;
    }
  return extents.xOff;
}

static int
xftfont_draw (s, from, to, x, y, with_background)
     struct glyph_string *s;
     int from, to, x, y, with_background;
{
  FRAME_PTR f = s->f;
  struct face *face = s->face;
  struct xftfont_info *xftfont_info = (struct xftfont_info *) face->font_info;
  struct xftface_info *xftface_info = (struct xftface_info *) face->extra;
  FT_UInt *code;
  XftColor fg, bg;
  XRectangle r;
  int len = to - from;
  int i;

  xftfont_get_colors (f, face, s->gc, xftface_info,
		      &fg, with_background ? &bg : NULL);
  BLOCK_INPUT;
  if (s->clip_width)
    {
      r.x = s->clip_x, r.width = s->clip_width;
      r.y = s->clip_y, r.height = s->clip_height;
      XftDrawSetClipRectangles (xftface_info->xft_draw, 0, 0, &r, 1);
    }
  if (with_background)
    {
      struct font *font = (struct font *) face->font_info;

      XftDrawRect (xftface_info->xft_draw, &bg,
		   x, y - face->font->ascent, s->width, font->font.height);
    }
  code = alloca (sizeof (FT_UInt) * len);
  for (i = 0; i < len; i++)
    code[i] = ((XCHAR2B_BYTE1 (s->char2b + from + i) << 8)
	       | XCHAR2B_BYTE2 (s->char2b + from + i));

  XftDrawGlyphs (xftface_info->xft_draw, &fg, xftfont_info->xftfont,
		 x, y, code, len);
  if (s->clip_width)
    XftDrawSetClip (xftface_info->xft_draw, NULL);
  UNBLOCK_INPUT;

  return len;
}

static int
xftfont_anchor_point (font, code, index, x, y)
     struct font *font;
     unsigned code;
     int index;
     int *x, *y;
{
  struct xftfont_info *xftfont_info = (struct xftfont_info *) font;
  FT_Face ft_face = xftfont_info->ft_face;

  if (FT_Load_Glyph (ft_face, code, FT_LOAD_DEFAULT) != 0)
    return -1;
  if (ft_face->glyph->format != FT_GLYPH_FORMAT_OUTLINE)
    return -1;
  if (index >= ft_face->glyph->outline.n_points)
    return -1;
  *x = ft_face->glyph->outline.points[index].x;
  *y = ft_face->glyph->outline.points[index].y;
  return 0;
}


void
syms_of_xftfont ()
{
  DEFSYM (Qxft, "xft");

  xftfont_driver = ftfont_driver;
  xftfont_driver.type = Qxft;
  xftfont_driver.get_cache = xfont_driver.get_cache;
  xftfont_driver.list = xftfont_list;
  xftfont_driver.match = xftfont_match;
  xftfont_driver.open = xftfont_open;
  xftfont_driver.close = xftfont_close;
  xftfont_driver.prepare_face = xftfont_prepare_face;
  xftfont_driver.done_face = xftfont_done_face;
  xftfont_driver.encode_char = xftfont_encode_char;
  xftfont_driver.text_extents = xftfont_text_extents;
  xftfont_driver.draw = xftfont_draw;
  xftfont_driver.anchor_point = xftfont_anchor_point;

  register_font_driver (&xftfont_driver, NULL);
}

/* arch-tag: 64ec61bf-7c8e-4fe6-b953-c6a85d5e1605
   (do not change this comment) */
