/* Implementation of GUI terminal on the Mac OS.
   Copyright (C) 2000, 2001, 2002, 2003, 2004, 2005 Free Software Foundation, Inc.

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

#include <config.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include "lisp.h"
#include "charset.h"
#include "blockinput.h"

#include "macterm.h"

#ifndef MAC_OSX
#include <alloca.h>
#endif

#if TARGET_API_MAC_CARBON
/* USE_CARBON_EVENTS determines if the Carbon Event Manager is used to
   obtain events from the event queue.  If set to 0, WaitNextEvent is
   used instead.  */
#define USE_CARBON_EVENTS 1
#else /* not TARGET_API_MAC_CARBON */
#include <Quickdraw.h>
#include <ToolUtils.h>
#include <Sound.h>
#include <Events.h>
#include <Script.h>
#include <Resources.h>
#include <Fonts.h>
#include <TextUtils.h>
#include <LowMem.h>
#include <Controls.h>
#include <Windows.h>
#if defined (__MRC__) || (__MSL__ >= 0x6000)
#include <ControlDefinitions.h>
#endif

#if __profile__
#include <profiler.h>
#endif
#endif /* not TARGET_API_MAC_CARBON */

#include "systty.h"
#include "systime.h"
#include "atimer.h"
#include "keymap.h"

#include <ctype.h>
#include <errno.h>
#include <setjmp.h>
#include <sys/stat.h>
#include <sys/param.h>

#include "keyboard.h"
#include "frame.h"
#include "dispextern.h"
#include "fontset.h"
#include "termhooks.h"
#include "termopts.h"
#include "termchar.h"
#include "gnu.h"
#include "disptab.h"
#include "buffer.h"
#include "window.h"
#include "intervals.h"
#include "composite.h"
#include "coding.h"

/* Set of macros that handle mapping of Mac modifier keys to emacs.  */
#define macCtrlKey     (NILP (Vmac_reverse_ctrl_meta) ? controlKey :	\
			(NILP (Vmac_command_key_is_meta) ? optionKey : cmdKey))
#define macShiftKey    (shiftKey)
#define macMetaKey     (NILP (Vmac_reverse_ctrl_meta) ?			\
			(NILP (Vmac_command_key_is_meta) ? optionKey : cmdKey) \
			: controlKey)
#define macAltKey      (NILP (Vmac_command_key_is_meta) ? cmdKey : optionKey)



/* Non-nil means Emacs uses toolkit scroll bars.  */

Lisp_Object Vx_toolkit_scroll_bars;

/* If Non-nil, the text will be rendered using Core Graphics text rendering which may anti-alias the text.  */
Lisp_Object Vmac_use_core_graphics;


/* Non-zero means that a HELP_EVENT has been generated since Emacs
   start.  */

static int any_help_event_p;

/* Non-zero means autoselect window with the mouse cursor.  */

int x_autoselect_window_p;

/* Non-zero means make use of UNDERLINE_POSITION font properties.  */

int x_use_underline_position_properties;

/* Non-zero means draw block and hollow cursor as wide as the glyph
   under it.  For example, if a block cursor is over a tab, it will be
   drawn as wide as that tab on the display.  */


/* This is a chain of structures for all the X displays currently in
   use.  */

struct x_display_info *x_display_list;

/* This is a list of cons cells, each of the form (NAME
   . FONT-LIST-CACHE), one for each element of x_display_list and in
   the same order.  NAME is the name of the frame.  FONT-LIST-CACHE
   records previous values returned by x-list-fonts.  */

Lisp_Object x_display_name_list;

/* This is display since Mac does not support multiple ones.  */
struct mac_display_info one_mac_display_info;

/* Frame being updated by update_frame.  This is declared in term.c.
   This is set by update_begin and looked at by all the XT functions.
   It is zero while not inside an update.  In that case, the XT
   functions assume that `selected_frame' is the frame to apply to.  */

extern struct frame *updating_frame;

extern int waiting_for_input;

/* This is a frame waiting to be auto-raised, within XTread_socket.  */

struct frame *pending_autoraise_frame;

/* Non-zero means user is interacting with a toolkit scroll bar.  */

static int toolkit_scroll_bar_interaction;

/* Mouse movement.

   Formerly, we used PointerMotionHintMask (in standard_event_mask)
   so that we would have to call XQueryPointer after each MotionNotify
   event to ask for another such event.  However, this made mouse tracking
   slow, and there was a bug that made it eventually stop.

   Simply asking for MotionNotify all the time seems to work better.

   In order to avoid asking for motion events and then throwing most
   of them away or busy-polling the server for mouse positions, we ask
   the server for pointer motion hints.  This means that we get only
   one event per group of mouse movements.  "Groups" are delimited by
   other kinds of events (focus changes and button clicks, for
   example), or by XQueryPointer calls; when one of these happens, we
   get another MotionNotify event the next time the mouse moves.  This
   is at least as efficient as getting motion events when mouse
   tracking is on, and I suspect only negligibly worse when tracking
   is off.  */

/* Where the mouse was last time we reported a mouse event.  */

static Rect last_mouse_glyph;
static Lisp_Object last_mouse_press_frame;

/* The scroll bar in which the last X motion event occurred.

   If the last X motion event occurred in a scroll bar, we set this so
   XTmouse_position can know whether to report a scroll bar motion or
   an ordinary motion.

   If the last X motion event didn't occur in a scroll bar, we set
   this to Qnil, to tell XTmouse_position to return an ordinary motion
   event.  */

static Lisp_Object last_mouse_scroll_bar;

/* This is a hack.  We would really prefer that XTmouse_position would
   return the time associated with the position it returns, but there
   doesn't seem to be any way to wrest the time-stamp from the server
   along with the position query.  So, we just keep track of the time
   of the last movement we received, and return that in hopes that
   it's somewhat accurate.  */

static Time last_mouse_movement_time;

struct scroll_bar *tracked_scroll_bar = NULL;

/* Incremented by XTread_socket whenever it really tries to read
   events.  */

#ifdef __STDC__
static int volatile input_signal_count;
#else
static int input_signal_count;
#endif

/* Used locally within XTread_socket.  */

static int x_noop_count;

/* Initial values of argv and argc.  */

extern char **initial_argv;
extern int initial_argc;

extern Lisp_Object Vcommand_line_args, Vsystem_name;

/* Tells if a window manager is present or not.  */

extern Lisp_Object Vx_no_window_manager;

extern int errno;

/* A mask of extra modifier bits to put into every keyboard char.  */

extern int extra_keyboard_modifiers;

/* The keysyms to use for the various modifiers.  */

static Lisp_Object Qalt, Qhyper, Qsuper, Qmodifier_value;

static Lisp_Object Qvendor_specific_keysyms;

#if 0
extern XrmDatabase x_load_resources P_ ((Display *, char *, char *, char *));
#endif

extern int inhibit_window_system;

#if __MRC__ && !TARGET_API_MAC_CARBON
QDGlobals qd;  /* QuickDraw global information structure.  */
#endif


struct frame * x_window_to_frame (struct mac_display_info *, WindowPtr);
struct mac_display_info *mac_display_info_for_display (Display *);
static void x_update_window_end P_ ((struct window *, int, int));
static void mac_handle_tool_bar_click P_ ((struct frame *, EventRecord *));
static int x_io_error_quitter P_ ((Display *));
int x_catch_errors P_ ((Display *));
void x_uncatch_errors P_ ((Display *, int));
void x_lower_frame P_ ((struct frame *));
void x_scroll_bar_clear P_ ((struct frame *));
int x_had_errors_p P_ ((Display *));
void x_wm_set_size_hint P_ ((struct frame *, long, int));
void x_raise_frame P_ ((struct frame *));
void x_set_window_size P_ ((struct frame *, int, int, int));
void x_wm_set_window_state P_ ((struct frame *, int));
void x_wm_set_icon_pixmap P_ ((struct frame *, int));
void mac_initialize P_ ((void));
static void x_font_min_bounds P_ ((XFontStruct *, int *, int *));
static int x_compute_min_glyph_bounds P_ ((struct frame *));
static void x_update_end P_ ((struct frame *));
static void XTframe_up_to_date P_ ((struct frame *));
static void XTreassert_line_highlight P_ ((int, int));
static void x_change_line_highlight P_ ((int, int, int, int));
static void XTset_terminal_modes P_ ((void));
static void XTreset_terminal_modes P_ ((void));
static void x_clear_frame P_ ((void));
static void frame_highlight P_ ((struct frame *));
static void frame_unhighlight P_ ((struct frame *));
static void x_new_focus_frame P_ ((struct x_display_info *, struct frame *));
static void XTframe_rehighlight P_ ((struct frame *));
static void x_frame_rehighlight P_ ((struct x_display_info *));
static void x_draw_hollow_cursor P_ ((struct window *, struct glyph_row *));
static void x_draw_bar_cursor P_ ((struct window *, struct glyph_row *, int,
				   enum text_cursor_kinds));

static void x_clip_to_row P_ ((struct window *, struct glyph_row *, int, GC));
static void x_flush P_ ((struct frame *f));
static void x_update_begin P_ ((struct frame *));
static void x_update_window_begin P_ ((struct window *));
static void x_after_update_window_line P_ ((struct glyph_row *));

void activate_scroll_bars (FRAME_PTR);
void deactivate_scroll_bars (FRAME_PTR);

static int is_emacs_window (WindowPtr);

int x_bitmap_icon (struct frame *, Lisp_Object);
void x_make_frame_visible (struct frame *);

extern void window_scroll (Lisp_Object, int, int, int);

/* Defined in macmenu.h.  */
extern void menubar_selection_callback (FRAME_PTR, int);
extern void set_frame_menubar (FRAME_PTR, int, int);

/* X display function emulation */

void
XFreePixmap (display, pixmap)
     Display *display;		/* not used */
     Pixmap pixmap;
{
  DisposeGWorld (pixmap);
}


/* Set foreground color for subsequent QuickDraw commands.  Assume
   graphic port has already been set.  */

static void
mac_set_forecolor (unsigned long color)
{
  RGBColor fg_color;

  fg_color.red = RED16_FROM_ULONG (color);
  fg_color.green = GREEN16_FROM_ULONG (color);
  fg_color.blue = BLUE16_FROM_ULONG (color);

  RGBForeColor (&fg_color);
}


/* Set background color for subsequent QuickDraw commands.  Assume
   graphic port has already been set.  */

static void
mac_set_backcolor (unsigned long color)
{
  RGBColor bg_color;

  bg_color.red = RED16_FROM_ULONG (color);
  bg_color.green = GREEN16_FROM_ULONG (color);
  bg_color.blue = BLUE16_FROM_ULONG (color);

  RGBBackColor (&bg_color);
}

/* Set foreground and background color for subsequent QuickDraw
   commands.  Assume that the graphic port has already been set.  */

static void
mac_set_colors (GC gc)
{
  mac_set_forecolor (gc->foreground);
  mac_set_backcolor (gc->background);
}

/* Mac version of XDrawLine.  */

static void
XDrawLine (display, w, gc, x1, y1, x2, y2)
     Display *display;
     WindowPtr w;
     GC gc;
     int x1, y1, x2, y2;
{
  SetPortWindowPort (w);

  mac_set_colors (gc);

  MoveTo (x1, y1);
  LineTo (x2, y2);
}

void
mac_draw_line_to_pixmap (display, p, gc, x1, y1, x2, y2)
     Display *display;
     Pixmap p;
     GC gc;
     int x1, y1, x2, y2;
{
  CGrafPtr old_port;
  GDHandle old_gdh;

  GetGWorld (&old_port, &old_gdh);
  SetGWorld (p, NULL);

  mac_set_colors (gc);

  LockPixels (GetGWorldPixMap (p));
  MoveTo (x1, y1);
  LineTo (x2, y2);
  UnlockPixels (GetGWorldPixMap (p));

  SetGWorld (old_port, old_gdh);
}

/* Mac version of XClearArea.  */

void
XClearArea (display, w, x, y, width, height, exposures)
     Display *display;
     WindowPtr w;
     int x, y;
     unsigned int width, height;
     int exposures;
{
  struct mac_output *mwp = (mac_output *) GetWRefCon (w);
  Rect r;
  XGCValues xgc;

  xgc.foreground = mwp->x_compatible.foreground_pixel;
  xgc.background = mwp->x_compatible.background_pixel;

  SetPortWindowPort (w);

  mac_set_colors (&xgc);
  SetRect (&r, x, y, x + width, y + height);

  EraseRect (&r);
}

/* Mac version of XClearWindow.  */

static void
XClearWindow (display, w)
     Display *display;
     WindowPtr w;
{
  struct mac_output *mwp = (mac_output *) GetWRefCon (w);
  XGCValues xgc;

  xgc.foreground = mwp->x_compatible.foreground_pixel;
  xgc.background = mwp->x_compatible.background_pixel;

  SetPortWindowPort (w);

  mac_set_colors (&xgc);

#if TARGET_API_MAC_CARBON
  {
    Rect r;

    GetWindowPortBounds (w, &r);
    EraseRect (&r);
  }
#else /* not TARGET_API_MAC_CARBON */
  EraseRect (&(w->portRect));
#endif /* not TARGET_API_MAC_CARBON */
}


/* Mac replacement for XCopyArea.  */

static void
mac_draw_bitmap (display, w, gc, x, y, width, height, bits, overlay_p)
     Display *display;
     WindowPtr w;
     GC gc;
     int x, y, width, height;
     unsigned short *bits;
     int overlay_p;
{
  BitMap bitmap;
  Rect r;

  bitmap.rowBytes = sizeof(unsigned short);
  bitmap.baseAddr = (char *)bits;
  SetRect (&(bitmap.bounds), 0, 0, width, height);

  SetPortWindowPort (w);

  mac_set_colors (gc);
  SetRect (&r, x, y, x + width, y + height);

#if TARGET_API_MAC_CARBON
  LockPortBits (GetWindowPort (w));
  CopyBits (&bitmap, GetPortBitMapForCopyBits (GetWindowPort (w)),
	    &(bitmap.bounds), &r, overlay_p ? srcOr : srcCopy, 0);
  UnlockPortBits (GetWindowPort (w));
#else /* not TARGET_API_MAC_CARBON */
  CopyBits (&bitmap, &(w->portBits), &(bitmap.bounds), &r,
	    overlay_p ? srcOr : srcCopy, 0);
#endif /* not TARGET_API_MAC_CARBON */
}


/* Mac replacement for XSetClipRectangles.  */

static void
mac_set_clip_rectangle (display, w, r)
     Display *display;
     WindowPtr w;
     Rect *r;
{
  SetPortWindowPort (w);

  ClipRect (r);
}


/* Mac replacement for XSetClipMask.  */

static void
mac_reset_clipping (display, w)
     Display *display;
     WindowPtr w;
{
  Rect r;

  SetPortWindowPort (w);

  SetRect (&r, -32767, -32767, 32767, 32767);
  ClipRect (&r);
}


/* Mac replacement for XCreateBitmapFromBitmapData.  */

static void
mac_create_bitmap_from_bitmap_data (bitmap, bits, w, h)
     BitMap *bitmap;
     char *bits;
     int w, h;
{
  static unsigned char swap_nibble[16]
    = { 0x0, 0x8, 0x4, 0xc,    /* 0000 1000 0100 1100 */
	0x2, 0xa, 0x6, 0xe,    /* 0010 1010 0110 1110 */
	0x1, 0x9, 0x5, 0xd,    /* 0001 1001 0101 1101 */
	0x3, 0xb, 0x7, 0xf };  /* 0011 1011 0111 1111 */
  int i, j, w1;
  char *p;

  w1 = (w + 7) / 8;         /* nb of 8bits elt in X bitmap */
  bitmap->rowBytes = ((w + 15) / 16) * 2; /* nb of 16bits elt in Mac bitmap */
  bitmap->baseAddr = xmalloc (bitmap->rowBytes * h);
  bzero (bitmap->baseAddr, bitmap->rowBytes * h);
  for (i = 0; i < h; i++)
    {
      p = bitmap->baseAddr + i * bitmap->rowBytes;
      for (j = 0; j < w1; j++)
	{
	  /* Bitswap XBM bytes to match how Mac does things.  */
	  unsigned char c = *bits++;
	  *p++ = (unsigned char)((swap_nibble[c & 0xf] << 4)
				 | (swap_nibble[(c>>4) & 0xf]));;
	}
    }

  SetRect (&(bitmap->bounds), 0, 0, w, h);
}


static void
mac_free_bitmap (bitmap)
     BitMap *bitmap;
{
  xfree (bitmap->baseAddr);
}


Pixmap
XCreatePixmap (display, w, width, height, depth)
     Display *display;		/* not used */
     WindowPtr w;
     unsigned int width, height;
     unsigned int depth;
{
  Pixmap pixmap;
  Rect r;
  QDErr err;

  SetPortWindowPort (w);

  SetRect (&r, 0, 0, width, height);
  err = NewGWorld (&pixmap, depth, &r, NULL, NULL, 0);
  if (err != noErr)
    return NULL;
  return pixmap;
}


Pixmap
XCreatePixmapFromBitmapData (display, w, data, width, height, fg, bg, depth)
     Display *display;		/* not used */
     WindowPtr w;
     char *data;
     unsigned int width, height;
     unsigned long fg, bg;
     unsigned int depth;	/* not used */
{
  Pixmap pixmap;
  BitMap bitmap;
  CGrafPtr old_port;
  GDHandle old_gdh;

  pixmap = XCreatePixmap (display, w, width, height, depth);
  if (pixmap == NULL)
    return NULL;

  GetGWorld (&old_port, &old_gdh);
  SetGWorld (pixmap, NULL);
  mac_create_bitmap_from_bitmap_data (&bitmap, data, width, height);
  mac_set_forecolor (fg);
  mac_set_backcolor (bg);
  LockPixels (GetGWorldPixMap (pixmap));
#if TARGET_API_MAC_CARBON
  CopyBits (&bitmap, GetPortBitMapForCopyBits (pixmap),
	    &bitmap.bounds, &bitmap.bounds, srcCopy, 0);
#else /* not TARGET_API_MAC_CARBON */
  CopyBits (&bitmap, &(((GrafPtr)pixmap)->portBits),
	    &bitmap.bounds, &bitmap.bounds, srcCopy, 0);
#endif /* not TARGET_API_MAC_CARBON */
  UnlockPixels (GetGWorldPixMap (pixmap));
  SetGWorld (old_port, old_gdh);
  mac_free_bitmap (&bitmap);

  return pixmap;
}


/* Mac replacement for XFillRectangle.  */

static void
XFillRectangle (display, w, gc, x, y, width, height)
     Display *display;
     WindowPtr w;
     GC gc;
     int x, y;
     unsigned int width, height;
{
  Rect r;

  SetPortWindowPort (w);

  mac_set_colors (gc);
  SetRect (&r, x, y, x + width, y + height);

  PaintRect (&r); /* using foreground color of gc */
}


#if 0 /* TODO: figure out if we need to do this on Mac.  */
static void
mac_fill_rectangle_to_pixmap (display, p, gc, x, y, width, height)
     Display *display;
     Pixmap p;
     GC gc;
     int x, y;
     unsigned int width, height;
{
  CGrafPtr old_port;
  GDHandle old_gdh;
  Rect r;

  GetGWorld (&old_port, &old_gdh);
  SetGWorld (p, NULL);
  mac_set_colors (gc);
  SetRect (&r, x, y, x + width, y + height);

  LockPixels (GetGWorldPixMap (p));
  PaintRect (&r); /* using foreground color of gc */
  UnlockPixels (GetGWorldPixMap (p));

  SetGWorld (old_port, old_gdh);
}
#endif


/* Mac replacement for XDrawRectangle: dest is a window.  */

static void
mac_draw_rectangle (display, w, gc, x, y, width, height)
     Display *display;
     WindowPtr w;
     GC gc;
     int x, y;
     unsigned int width, height;
{
  Rect r;

  SetPortWindowPort (w);

  mac_set_colors (gc);
  SetRect (&r, x, y, x + width + 1, y + height + 1);

  FrameRect (&r); /* using foreground color of gc */
}


#if 0 /* TODO: figure out if we need to do this on Mac.  */
/* Mac replacement for XDrawRectangle: dest is a Pixmap.  */

static void
mac_draw_rectangle_to_pixmap (display, p, gc, x, y, width, height)
     Display *display;
     Pixmap p;
     GC gc;
     int x, y;
     unsigned int width, height;
{
  CGrafPtr old_port;
  GDHandle old_gdh;
  Rect r;

  GetGWorld (&old_port, &old_gdh);
  SetGWorld (p, NULL);
  mac_set_colors (gc);
  SetRect (&r, x, y, x + width + 1, y + height + 1);

  LockPixels (GetGWorldPixMap (p));
  FrameRect (&r); /* using foreground color of gc */
  UnlockPixels (GetGWorldPixMap (p));

  SetGWorld (old_port, old_gdh);
}
#endif


static void
mac_draw_string_common (display, w, gc, x, y, buf, nchars, mode,
			bytes_per_char)
     Display *display;
     WindowPtr w;
     GC gc;
     int x, y;
     char *buf;
     int nchars, mode, bytes_per_char;
{
  SetPortWindowPort (w);
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1020
  UInt32 textFlags, savedFlags;
  if (!NILP(Vmac_use_core_graphics)) {
    textFlags = kQDUseCGTextRendering;
    savedFlags = SwapQDTextFlags(textFlags);
  }
#endif

  mac_set_colors (gc);

  TextFont (gc->font->mac_fontnum);
  TextSize (gc->font->mac_fontsize);
  TextFace (gc->font->mac_fontface);
  TextMode (mode);

  MoveTo (x, y);
  DrawText (buf, 0, nchars * bytes_per_char);
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1020
  if (!NILP(Vmac_use_core_graphics))
    SwapQDTextFlags(savedFlags);
#endif
}


/* Mac replacement for XDrawString.  */

static void
XDrawString (display, w, gc, x, y, buf, nchars)
     Display *display;
     WindowPtr w;
     GC gc;
     int x, y;
     char *buf;
     int nchars;
{
  mac_draw_string_common (display, w, gc, x, y, buf, nchars, srcOr, 1);
}


/* Mac replacement for XDrawString16. */

static void
XDrawString16 (display, w, gc, x, y, buf, nchars)
     Display *display;
     WindowPtr w;
     GC gc;
     int x, y;
     XChar2b *buf;
     int nchars;
{
  mac_draw_string_common (display, w, gc, x, y, (char *) buf, nchars, srcOr,
			  2);
}


/* Mac replacement for XDrawImageString.  */

static void
XDrawImageString (display, w, gc, x, y, buf, nchars)
     Display *display;
     WindowPtr w;
     GC gc;
     int x, y;
     char *buf;
     int nchars;
{
  mac_draw_string_common (display, w, gc, x, y, buf, nchars, srcCopy, 1);
}


/* Mac replacement for XDrawString16.  */

static void
XDrawImageString16 (display, w, gc, x, y, buf, nchars)
     Display *display;
     WindowPtr w;
     GC gc;
     int x, y;
     XChar2b *buf;
     int nchars;
{
  mac_draw_string_common (display, w, gc, x, y, (char *) buf, nchars, srcCopy,
			  2);
}


/* Mac replacement for XCopyArea: dest must be window.  */

static void
mac_copy_area (display, src, dest, gc, src_x, src_y, width, height, dest_x,
	       dest_y)
     Display *display;
     Pixmap src;
     WindowPtr dest;
     GC gc;
     int src_x, src_y;
     unsigned int width, height;
     int dest_x, dest_y;
{
  Rect src_r, dest_r;

  SetPortWindowPort (dest);

  SetRect (&src_r, src_x, src_y, src_x + width, src_y + height);
  SetRect (&dest_r, dest_x, dest_y, dest_x + width, dest_y + height);

  ForeColor (blackColor);
  BackColor (whiteColor);

  LockPixels (GetGWorldPixMap (src));
#if TARGET_API_MAC_CARBON
  LockPortBits (GetWindowPort (dest));
  CopyBits (GetPortBitMapForCopyBits (src),
	    GetPortBitMapForCopyBits (GetWindowPort (dest)),
	    &src_r, &dest_r, srcCopy, 0);
  UnlockPortBits (GetWindowPort (dest));
#else /* not TARGET_API_MAC_CARBON */
  CopyBits (&(((GrafPtr)src)->portBits), &(dest->portBits),
	    &src_r, &dest_r, srcCopy, 0);
#endif /* not TARGET_API_MAC_CARBON */
  UnlockPixels (GetGWorldPixMap (src));
}


static void
mac_copy_area_with_mask (display, src, mask, dest, gc, src_x, src_y,
			 width, height, dest_x, dest_y)
     Display *display;
     Pixmap src, mask;
     WindowPtr dest;
     GC gc;
     int src_x, src_y;
     unsigned int width, height;
     int dest_x, dest_y;
{
  Rect src_r, dest_r;

  SetPortWindowPort (dest);

  SetRect (&src_r, src_x, src_y, src_x + width, src_y + height);
  SetRect (&dest_r, dest_x, dest_y, dest_x + width, dest_y + height);

  ForeColor (blackColor);
  BackColor (whiteColor);

  LockPixels (GetGWorldPixMap (src));
  LockPixels (GetGWorldPixMap (mask));
#if TARGET_API_MAC_CARBON
  LockPortBits (GetWindowPort (dest));
  CopyMask (GetPortBitMapForCopyBits (src), GetPortBitMapForCopyBits (mask),
	    GetPortBitMapForCopyBits (GetWindowPort (dest)),
	    &src_r, &src_r, &dest_r);
  UnlockPortBits (GetWindowPort (dest));
#else /* not TARGET_API_MAC_CARBON */
  CopyMask (&(((GrafPtr)src)->portBits), &(((GrafPtr)mask)->portBits),
	    &(dest->portBits), &src_r, &src_r, &dest_r);
#endif /* not TARGET_API_MAC_CARBON */
  UnlockPixels (GetGWorldPixMap (mask));
  UnlockPixels (GetGWorldPixMap (src));
}


#if 0
/* Convert a pair of local coordinates to global (screen) coordinates.
   Assume graphic port has been properly set.  */
static void
local_to_global_coord (short *h, short *v)
{
  Point p;

  p.h = *h;
  p.v = *v;

  LocalToGlobal (&p);

  *h = p.h;
  *v = p.v;
}
#endif

/* Mac replacement for XCopyArea: used only for scrolling.  */

static void
mac_scroll_area (display, w, gc, src_x, src_y, width, height, dest_x, dest_y)
     Display *display;
     WindowPtr w;
     GC gc;
     int src_x, src_y;
     unsigned int width, height;
     int dest_x, dest_y;
{
#if TARGET_API_MAC_CARBON
  Rect src_r;
  RgnHandle dummy = NewRgn ();	/* For avoiding update events.  */

  SetRect (&src_r, src_x, src_y, src_x + width, src_y + height);
  ScrollWindowRect (w, &src_r, dest_x - src_x, dest_y - src_y,
		    kScrollWindowNoOptions, dummy);
  DisposeRgn (dummy);
#else /* not TARGET_API_MAC_CARBON */
  Rect src_r, dest_r;

  SetPort (w);
#if 0
  mac_set_colors (gc);
#endif

  SetRect (&src_r, src_x, src_y, src_x + width, src_y + height);
  SetRect (&dest_r, dest_x, dest_y, dest_x + width, dest_y + height);

#if 0
  /* Need to use global coordinates and screenBits since src and dest
     areas overlap in general.  */
  local_to_global_coord (&src_r.left, &src_r.top);
  local_to_global_coord (&src_r.right, &src_r.bottom);
  local_to_global_coord (&dest_r.left, &dest_r.top);
  local_to_global_coord (&dest_r.right, &dest_r.bottom);

  CopyBits (&qd.screenBits, &qd.screenBits, &src_r, &dest_r, srcCopy, 0);
#else
  /* In Color QuickDraw, set ForeColor and BackColor as follows to avoid
     color mapping in CopyBits.  Otherwise, it will be slow.  */
  ForeColor (blackColor);
  BackColor (whiteColor);
  CopyBits (&(w->portBits), &(w->portBits), &src_r, &dest_r, srcCopy, 0);

  mac_set_colors (gc);
#endif
#endif /* not TARGET_API_MAC_CARBON */
}


#if 0 /* TODO: figure out if we need to do this on Mac.  */
/* Mac replacement for XCopyArea: dest must be Pixmap.  */

static void
mac_copy_area_to_pixmap (display, src, dest, gc, src_x, src_y, width, height,
                     dest_x, dest_y)
     Display *display;
     Pixmap src, dest;
     GC gc;
     int src_x, src_y;
     unsigned int width, height;
     int dest_x, dest_y;
{
  CGrafPtr old_port;
  GDHandle old_gdh;
  Rect src_r, dest_r;

  GetGWorld (&old_port, &old_gdh);
  SetGWorld (dest, NULL);
  ForeColor (blackColor);
  BackColor (whiteColor);

  SetRect (&src_r, src_x, src_y, src_x + width, src_y + height);
  SetRect (&dest_r, dest_x, dest_y, dest_x + width, dest_y + height);

  LockPixels (GetGWorldPixMap (src));
  LockPixels (GetGWorldPixMap (dest));
#if TARGET_API_MAC_CARBON
  CopyBits (GetPortBitMapForCopyBits (src), GetPortBitMapForCopyBits (dest),
	    &src_r, &dest_r, srcCopy, 0);
#else /* not TARGET_API_MAC_CARBON */
  CopyBits (&(((GrafPtr)src)->portBits), &(((GrafPtr)dest)->portBits),
	    &src_r, &dest_r, srcCopy, 0);
#endif /* not TARGET_API_MAC_CARBON */
  UnlockPixels (GetGWorldPixMap (dest));
  UnlockPixels (GetGWorldPixMap (src));

  SetGWorld (old_port, old_gdh);
}


static void
mac_copy_area_with_mask_to_pixmap (display, src, mask, dest, gc, src_x, src_y,
				   width, height, dest_x, dest_y)
     Display *display;
     Pixmap src, mask, dest;
     GC gc;
     int src_x, src_y;
     unsigned int width, height;
     int dest_x, dest_y;
{
  CGrafPtr old_port;
  GDHandle old_gdh;
  Rect src_r, dest_r;

  GetGWorld (&old_port, &old_gdh);
  SetGWorld (dest, NULL);
  ForeColor (blackColor);
  BackColor (whiteColor);

  SetRect (&src_r, src_x, src_y, src_x + width, src_y + height);
  SetRect (&dest_r, dest_x, dest_y, dest_x + width, dest_y + height);

  LockPixels (GetGWorldPixMap (src));
  LockPixels (GetGWorldPixMap (mask));
  LockPixels (GetGWorldPixMap (dest));
#if TARGET_API_MAC_CARBON
  CopyMask (GetPortBitMapForCopyBits (src), GetPortBitMapForCopyBits (mask),
	    GetPortBitMapForCopyBits (dest), &src_r, &src_r, &dest_r);
#else /* not TARGET_API_MAC_CARBON */
  CopyMask (&(((GrafPtr)src)->portBits), &(((GrafPtr)mask)->portBits),
	    &(((GrafPtr)dest)->portBits), &src_r, &src_r, &dest_r);
#endif /* not TARGET_API_MAC_CARBON */
  UnlockPixels (GetGWorldPixMap (dest));
  UnlockPixels (GetGWorldPixMap (mask));
  UnlockPixels (GetGWorldPixMap (src));

  SetGWorld (old_port, old_gdh);
}
#endif


/* Mac replacement for XChangeGC.  */

static void
XChangeGC (void * ignore, XGCValues* gc, unsigned long mask,
                XGCValues *xgcv)
{
  if (mask & GCForeground)
    gc->foreground = xgcv->foreground;
  if (mask & GCBackground)
    gc->background = xgcv->background;
  if (mask & GCFont)
    gc->font = xgcv->font;
}


/* Mac replacement for XCreateGC.  */

XGCValues *
XCreateGC (void * ignore, Window window, unsigned long mask,
                      XGCValues *xgcv)
{
  XGCValues *gc = (XGCValues *) xmalloc (sizeof (XGCValues));
  bzero (gc, sizeof (XGCValues));

  XChangeGC (ignore, gc, mask, xgcv);

  return gc;
}


/* Used in xfaces.c.  */

void
XFreeGC (display, gc)
     Display *display;
     GC gc;
{
  xfree (gc);
}


/* Mac replacement for XGetGCValues.  */

static void
XGetGCValues (void* ignore, XGCValues *gc,
                   unsigned long mask, XGCValues *xgcv)
{
  XChangeGC (ignore, xgcv, mask, gc);
}


/* Mac replacement for XSetForeground.  */

void
XSetForeground (display, gc, color)
     Display *display;
     GC gc;
     unsigned long color;
{
  gc->foreground = color;
}


/* Mac replacement for XSetBackground.  */

void
XSetBackground (display, gc, color)
     Display *display;
     GC gc;
     unsigned long color;
{
  gc->background = color;
}


/* Mac replacement for XSetWindowBackground.  */

void
XSetWindowBackground (display, w, color)
     Display *display;
     WindowPtr w;
     unsigned long color;
{
#if !TARGET_API_MAC_CARBON
  AuxWinHandle aw_handle;
  CTabHandle ctab_handle;
  ColorSpecPtr ct_table;
  short ct_size;
#endif
  RGBColor bg_color;

  bg_color.red = RED16_FROM_ULONG (color);
  bg_color.green = GREEN16_FROM_ULONG (color);
  bg_color.blue = BLUE16_FROM_ULONG (color);

#if TARGET_API_MAC_CARBON
  SetWindowContentColor (w, &bg_color);
#else
  if (GetAuxWin (w, &aw_handle))
    {
      ctab_handle = (*aw_handle)->awCTable;
      HandToHand ((Handle *) &ctab_handle);
      ct_table = (*ctab_handle)->ctTable;
      ct_size = (*ctab_handle)->ctSize;
      while (ct_size > -1)
	{
	  if (ct_table->value == 0)
	    {
	      ct_table->rgb = bg_color;
	      CTabChanged (ctab_handle);
	      SetWinColor (w, (WCTabHandle) ctab_handle);
	    }
	  ct_size--;
	}
    }
#endif
}


/* Mac replacement for XSetFont.  */

static void
XSetFont (display, gc, font)
     Display *display;
     GC gc;
     XFontStruct *font;
{
  gc->font = font;
}


static void
XTextExtents16 (XFontStruct *font, XChar2b *text, int nchars,
                     int *direction,int *font_ascent,
                     int *font_descent, XCharStruct *cs)
{
  /* MAC_TODO: Use GetTextMetrics to do this and inline it below. */
}


/* x_sync is a no-op on Mac.  */
void
x_sync (f)
     void *f;
{
}


/* Flush display of frame F, or of all frames if F is null.  */

static void
x_flush (f)
     struct frame *f;
{
#if TARGET_API_MAC_CARBON
  BLOCK_INPUT;
  if (f)
    QDFlushPortBuffer (GetWindowPort (FRAME_MAC_WINDOW (f)), NULL);
  else
    QDFlushPortBuffer (GetQDGlobalsThePort (), NULL);
  UNBLOCK_INPUT;
#endif
}


/* Remove calls to XFlush by defining XFlush to an empty replacement.
   Calls to XFlush should be unnecessary because the X output buffer
   is flushed automatically as needed by calls to XPending,
   XNextEvent, or XWindowEvent according to the XFlush man page.
   XTread_socket calls XPending.  Removing XFlush improves
   performance.  */

#define XFlush(DISPLAY)	(void) 0


/* Return the struct mac_display_info corresponding to DPY.  There's
   only one.  */

struct mac_display_info *
mac_display_info_for_display (dpy)
     Display *dpy;
{
  return &one_mac_display_info;
}



/***********************************************************************
		    Starting and ending an update
 ***********************************************************************/

/* Start an update of frame F.  This function is installed as a hook
   for update_begin, i.e. it is called when update_begin is called.
   This function is called prior to calls to x_update_window_begin for
   each window being updated.  */

static void
x_update_begin (f)
     struct frame *f;
{
#if TARGET_API_MAC_CARBON
  /* During update of a frame, availability of input events is
     periodically checked with ReceiveNextEvent if
     redisplay-dont-pause is nil.  That normally flushes window buffer
     changes for every check, and thus screen update looks waving even
     if no input is available.  So we disable screen updates during
     update of a frame.  */
  BLOCK_INPUT;
  DisableScreenUpdates ();
  UNBLOCK_INPUT;
#endif
}


/* Start update of window W.  Set the global variable updated_window
   to the window being updated and set output_cursor to the cursor
   position of W.  */

static void
x_update_window_begin (w)
     struct window *w;
{
  struct frame *f = XFRAME (WINDOW_FRAME (w));
  struct mac_display_info *display_info = FRAME_MAC_DISPLAY_INFO (f);

  updated_window = w;
  set_output_cursor (&w->cursor);

  BLOCK_INPUT;

  if (f == display_info->mouse_face_mouse_frame)
    {
      /* Don't do highlighting for mouse motion during the update.  */
      display_info->mouse_face_defer = 1;

      /* If F needs to be redrawn, simply forget about any prior mouse
	 highlighting.  */
      if (FRAME_GARBAGED_P (f))
	display_info->mouse_face_window = Qnil;

#if 0 /* Rows in a current matrix containing glyphs in mouse-face have
	 their mouse_face_p flag set, which means that they are always
	 unequal to rows in a desired matrix which never have that
	 flag set.  So, rows containing mouse-face glyphs are never
	 scrolled, and we don't have to switch the mouse highlight off
	 here to prevent it from being scrolled.  */

      /* Can we tell that this update does not affect the window
	 where the mouse highlight is?  If so, no need to turn off.
	 Likewise, don't do anything if the frame is garbaged;
	 in that case, the frame's current matrix that we would use
	 is all wrong, and we will redisplay that line anyway.  */
      if (!NILP (display_info->mouse_face_window)
	  && w == XWINDOW (display_info->mouse_face_window))
	{
	  int i;

	  for (i = 0; i < w->desired_matrix->nrows; ++i)
	    if (MATRIX_ROW_ENABLED_P (w->desired_matrix, i))
	      break;

	  if (i < w->desired_matrix->nrows)
	    clear_mouse_face (display_info);
	}
#endif /* 0 */
    }

  UNBLOCK_INPUT;
}


/* Draw a vertical window border from (x,y0) to (x,y1)  */

static void
mac_draw_vertical_window_border (w, x, y0, y1)
     struct window *w;
     int x, y0, y1;
{
  struct frame *f = XFRAME (WINDOW_FRAME (w));

  XDrawLine (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
	     f->output_data.mac->normal_gc, x, y0, x, y1);
}


/* End update of window W (which is equal to updated_window).

   Draw vertical borders between horizontally adjacent windows, and
   display W's cursor if CURSOR_ON_P is non-zero.

   MOUSE_FACE_OVERWRITTEN_P non-zero means that some row containing
   glyphs in mouse-face were overwritten.  In that case we have to
   make sure that the mouse-highlight is properly redrawn.

   W may be a menu bar pseudo-window in case we don't have X toolkit
   support.  Such windows don't have a cursor, so don't display it
   here. */

static void
x_update_window_end (w, cursor_on_p, mouse_face_overwritten_p)
     struct window *w;
     int cursor_on_p, mouse_face_overwritten_p;
{
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (XFRAME (w->frame));

  if (!w->pseudo_window_p)
    {
      BLOCK_INPUT;

      if (cursor_on_p)
	display_and_set_cursor (w, 1, output_cursor.hpos,
				output_cursor.vpos,
				output_cursor.x, output_cursor.y);

      if (draw_window_fringes (w, 1))
	x_draw_vertical_border (w);

      UNBLOCK_INPUT;
    }

  /* If a row with mouse-face was overwritten, arrange for
     XTframe_up_to_date to redisplay the mouse highlight.  */
  if (mouse_face_overwritten_p)
    {
      dpyinfo->mouse_face_beg_row = dpyinfo->mouse_face_beg_col = -1;
      dpyinfo->mouse_face_end_row = dpyinfo->mouse_face_end_col = -1;
      dpyinfo->mouse_face_window = Qnil;
    }

#if 0
  /* Unhide the caret.  This won't actually show the cursor, unless it
     was visible before the corresponding call to HideCaret in
     x_update_window_begin.  */
  if (w32_use_visible_system_caret)
    SendMessage (w32_system_caret_hwnd, WM_EMACS_SHOW_CARET, 0, 0);
#endif

  updated_window = NULL;
}


/* End update of frame F.  This function is installed as a hook in
   update_end.  */

static void
x_update_end (f)
     struct frame *f;
{
  /* Mouse highlight may be displayed again.  */
  FRAME_MAC_DISPLAY_INFO (f)->mouse_face_defer = 0;

  BLOCK_INPUT;
  /* Reset the background color of Mac OS Window to that of the frame after
     update so that it is used by Mac Toolbox to clear the update region before
     an update event is generated.  */
  SetPortWindowPort (FRAME_MAC_WINDOW (f));

  mac_set_backcolor (FRAME_BACKGROUND_PIXEL (f));

#if TARGET_API_MAC_CARBON
  EnableScreenUpdates ();
#endif
  XFlush (FRAME_MAC_DISPLAY (f));
  UNBLOCK_INPUT;
}


/* This function is called from various places in xdisp.c whenever a
   complete update has been performed.  The global variable
   updated_window is not available here.  */

static void
XTframe_up_to_date (f)
     struct frame *f;
{
  if (FRAME_MAC_P (f))
    {
      struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (f);

      if (dpyinfo->mouse_face_deferred_gc
	  || f == dpyinfo->mouse_face_mouse_frame)
	{
	  BLOCK_INPUT;
	  if (dpyinfo->mouse_face_mouse_frame)
	    note_mouse_highlight (dpyinfo->mouse_face_mouse_frame,
				  dpyinfo->mouse_face_mouse_x,
				  dpyinfo->mouse_face_mouse_y);
	  dpyinfo->mouse_face_deferred_gc = 0;
	  UNBLOCK_INPUT;
	}
    }
}


/* Draw truncation mark bitmaps, continuation mark bitmaps, overlay
   arrow bitmaps, or clear the fringes if no bitmaps are required
   before DESIRED_ROW is made current.  The window being updated is
   found in updated_window.  This function is called from
   update_window_line only if it is known that there are differences
   between bitmaps to be drawn between current row and DESIRED_ROW.  */

static void
x_after_update_window_line (desired_row)
     struct glyph_row *desired_row;
{
  struct window *w = updated_window;
  struct frame *f;
  int width, height;

  xassert (w);

  if (!desired_row->mode_line_p && !w->pseudo_window_p)
    desired_row->redraw_fringe_bitmaps_p = 1;

  /* When a window has disappeared, make sure that no rest of
     full-width rows stays visible in the internal border.  Could
     check here if updated_window is the leftmost/rightmost window,
     but I guess it's not worth doing since vertically split windows
     are almost never used, internal border is rarely set, and the
     overhead is very small.  */
  if (windows_or_buffers_changed
      && desired_row->full_width_p
      && (f = XFRAME (w->frame),
	  width = FRAME_INTERNAL_BORDER_WIDTH (f),
	  width != 0)
      && (height = desired_row->visible_height,
	  height > 0))
    {
      int y = WINDOW_TO_FRAME_PIXEL_Y (w, max (0, desired_row->y));
      /* Internal border is drawn below the tool bar.  */
      if (WINDOWP (f->tool_bar_window)
	  && w == XWINDOW (f->tool_bar_window))
	y -= width;

      BLOCK_INPUT;

      XClearArea (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
		  0, y, width, height, 0);
      XClearArea (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
		  FRAME_PIXEL_WIDTH (f) - width, y,
		  width, height, 0);

      UNBLOCK_INPUT;
    }
}


/* Draw the bitmap WHICH in one of the left or right fringes of
   window W.  ROW is the glyph row for which to display the bitmap; it
   determines the vertical position at which the bitmap has to be
   drawn.  */

static void
x_draw_fringe_bitmap (w, row, p)
     struct window *w;
     struct glyph_row *row;
     struct draw_fringe_bitmap_params *p;
{
  struct frame *f = XFRAME (WINDOW_FRAME (w));
  Display *display = FRAME_MAC_DISPLAY (f);
  WindowPtr window = FRAME_MAC_WINDOW (f);
  XGCValues gcv;
  GC gc = f->output_data.mac->normal_gc;
  struct face *face = p->face;
  int rowY;

  /* Must clip because of partially visible lines.  */
  rowY = WINDOW_TO_FRAME_PIXEL_Y (w, row->y);
  if (p->y < rowY)
    {
      /* Adjust position of "bottom aligned" bitmap on partially
	 visible last row.  */
      int oldY = row->y;
      int oldVH = row->visible_height;
      row->visible_height = p->h;
      row->y -= rowY - p->y;
      x_clip_to_row (w, row, -1, gc);
      row->y = oldY;
      row->visible_height = oldVH;
    }
  else
    x_clip_to_row (w, row, -1, gc);

  if (p->bx >= 0 && !p->overlay_p)
    {
      XGCValues gcv;
      gcv.foreground = face->background;

#if 0  /* MAC_TODO: stipple */
      /* In case the same realized face is used for fringes and
	 for something displayed in the text (e.g. face `region' on
	 mono-displays, the fill style may have been changed to
	 FillSolid in x_draw_glyph_string_background.  */
      if (face->stipple)
	XSetFillStyle (FRAME_X_DISPLAY (f), face->gc, FillOpaqueStippled);
      else
	XSetForeground (FRAME_X_DISPLAY (f), face->gc, face->background);
#endif

      XFillRectangle (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
		      &gcv,
		      p->bx, p->by, p->nx, p->ny);

#if 0  /* MAC_TODO: stipple */
      if (!face->stipple)
	XSetForeground (FRAME_X_DISPLAY (f), face->gc, face->foreground);
#endif
    }

  if (p->which)
    {
      unsigned short *bits = p->bits + p->dh;

      gcv.foreground = (p->cursor_p
			? (p->overlay_p ? face->background
			   : f->output_data.mac->cursor_pixel)
			: face->foreground);
      gcv.background = face->background;

      mac_draw_bitmap (display, window, &gcv, p->x, p->y,
		       p->wd, p->h, bits, p->overlay_p);
    }

  mac_reset_clipping (display, window);
}


/* This is called when starting Emacs and when restarting after
   suspend.  When starting Emacs, no window is mapped.  And nothing
   must be done to Emacs's own window if it is suspended (though that
   rarely happens).  */

static void
XTset_terminal_modes ()
{
}

/* This is called when exiting or suspending Emacs.  Exiting will make
   the windows go away, and suspending requires no action.  */

static void
XTreset_terminal_modes ()
{
}


/***********************************************************************
			   Display Iterator
 ***********************************************************************/

/* Function prototypes of this page.  */

static XCharStruct *x_per_char_metric P_ ((XFontStruct *, XChar2b *));
static int mac_encode_char P_ ((int, XChar2b *, struct font_info *, int *));


/* Return a pointer to per-char metric information in FONT of a
   character pointed by B which is a pointer to an XChar2b.  */

#define PER_CHAR_METRIC(font, b)					   \
  ((font)->per_char							   \
   ? ((font)->per_char + (b)->byte2 - (font)->min_char_or_byte2		   \
      + (((font)->min_byte1 || (font)->max_byte1)			   \
	 ? (((b)->byte1 - (font)->min_byte1)				   \
	    * ((font)->max_char_or_byte2 - (font)->min_char_or_byte2 + 1)) \
	 : 0))								   \
   : &((font)->max_bounds))


/* Get metrics of character CHAR2B in FONT.  Value is null if CHAR2B
   is not contained in the font.  */

static INLINE XCharStruct *
x_per_char_metric (font, char2b)
     XFontStruct *font;
     XChar2b *char2b;
{
  /* The result metric information.  */
  XCharStruct *pcm = NULL;

  xassert (font && char2b);

  if (font->per_char != NULL)
    {
      if (font->min_byte1 == 0 && font->max_byte1 == 0)
	{
	  /* min_char_or_byte2 specifies the linear character index
	     corresponding to the first element of the per_char array,
	     max_char_or_byte2 is the index of the last character.  A
	     character with non-zero CHAR2B->byte1 is not in the font.
	     A character with byte2 less than min_char_or_byte2 or
	     greater max_char_or_byte2 is not in the font.  */
	  if (char2b->byte1 == 0
	      && char2b->byte2 >= font->min_char_or_byte2
	      && char2b->byte2 <= font->max_char_or_byte2)
	    pcm = font->per_char + char2b->byte2 - font->min_char_or_byte2;
	}
      else
	{
	  /* If either min_byte1 or max_byte1 are nonzero, both
	     min_char_or_byte2 and max_char_or_byte2 are less than
	     256, and the 2-byte character index values corresponding
	     to the per_char array element N (counting from 0) are:

	     byte1 = N/D + min_byte1
	     byte2 = N\D + min_char_or_byte2

	     where:

	     D = max_char_or_byte2 - min_char_or_byte2 + 1
	     / = integer division
	     \ = integer modulus  */
	  if (char2b->byte1 >= font->min_byte1
	      && char2b->byte1 <= font->max_byte1
	      && char2b->byte2 >= font->min_char_or_byte2
	      && char2b->byte2 <= font->max_char_or_byte2)
	    {
	      pcm = (font->per_char
		     + ((font->max_char_or_byte2 - font->min_char_or_byte2 + 1)
			* (char2b->byte1 - font->min_byte1))
		     + (char2b->byte2 - font->min_char_or_byte2));
	    }
	}
    }
  else
    {
      /* If the per_char pointer is null, all glyphs between the first
	 and last character indexes inclusive have the same
	 information, as given by both min_bounds and max_bounds.  */
      if (char2b->byte2 >= font->min_char_or_byte2
	  && char2b->byte2 <= font->max_char_or_byte2)
	pcm = &font->max_bounds;
    }

  return ((pcm == NULL
	   || (pcm->width == 0 && (pcm->rbearing - pcm->lbearing) == 0))
	  ? NULL : pcm);
}

/* RIF:
 */

static XCharStruct *
mac_per_char_metric (font, char2b, font_type)
     XFontStruct *font;
     XChar2b *char2b;
     int font_type;
{
  return x_per_char_metric (font, char2b);
}

/* RIF:
   Encode CHAR2B using encoding information from FONT_INFO.  CHAR2B is
   the two-byte form of C.  Encoding is returned in *CHAR2B.  */

static int
mac_encode_char (c, char2b, font_info, two_byte_p)
     int c;
     XChar2b *char2b;
     struct font_info *font_info;
     int *two_byte_p;
{
  int charset = CHAR_CHARSET (c);
  XFontStruct *font = font_info->font;

  /* FONT_INFO may define a scheme by which to encode byte1 and byte2.
     This may be either a program in a special encoder language or a
     fixed encoding.  */
  if (font_info->font_encoder)
    {
      /* It's a program.  */
      struct ccl_program *ccl = font_info->font_encoder;

      if (CHARSET_DIMENSION (charset) == 1)
	{
	  ccl->reg[0] = charset;
	  ccl->reg[1] = char2b->byte2;
	}
      else
	{
	  ccl->reg[0] = charset;
	  ccl->reg[1] = char2b->byte1;
	  ccl->reg[2] = char2b->byte2;
	}

      ccl_driver (ccl, NULL, NULL, 0, 0, NULL);

      /* We assume that MSBs are appropriately set/reset by CCL
	 program.  */
      if (font->max_byte1 == 0)	/* 1-byte font */
	char2b->byte1 = 0, char2b->byte2 = ccl->reg[1];
      else
	char2b->byte1 = ccl->reg[1], char2b->byte2 = ccl->reg[2];
    }
  else if (font_info->encoding[charset])
    {
      /* Fixed encoding scheme.  See fontset.h for the meaning of the
	 encoding numbers.  */
      int enc = font_info->encoding[charset];

      if ((enc == 1 || enc == 2)
	  && CHARSET_DIMENSION (charset) == 2)
	char2b->byte1 |= 0x80;

      if (enc == 1 || enc == 3)
	char2b->byte2 |= 0x80;

      if (enc == 4)
        {
          int sjis1, sjis2;

          ENCODE_SJIS (char2b->byte1, char2b->byte2, sjis1, sjis2);
          char2b->byte1 = sjis1;
          char2b->byte2 = sjis2;
        }
    }

  if (two_byte_p)
    *two_byte_p = ((XFontStruct *) (font_info->font))->max_byte1 > 0;

  return FONT_TYPE_UNKNOWN;
}



/***********************************************************************
			    Glyph display
 ***********************************************************************/


static void x_set_glyph_string_clipping P_ ((struct glyph_string *));
static void x_set_glyph_string_gc P_ ((struct glyph_string *));
static void x_draw_glyph_string_background P_ ((struct glyph_string *,
						int));
static void x_draw_glyph_string_foreground P_ ((struct glyph_string *));
static void x_draw_composite_glyph_string_foreground P_ ((struct glyph_string *));
static void x_draw_glyph_string_box P_ ((struct glyph_string *));
static void x_draw_glyph_string  P_ ((struct glyph_string *));
static void x_set_cursor_gc P_ ((struct glyph_string *));
static void x_set_mode_line_face_gc P_ ((struct glyph_string *));
static void x_set_mouse_face_gc P_ ((struct glyph_string *));
/*static int x_alloc_lighter_color P_ ((struct frame *, Display *, Colormap,
  unsigned long *, double, int));*/
static void x_setup_relief_color P_ ((struct frame *, struct relief *,
				      double, int, unsigned long));
static void x_setup_relief_colors P_ ((struct glyph_string *));
static void x_draw_image_glyph_string P_ ((struct glyph_string *));
static void x_draw_image_relief P_ ((struct glyph_string *));
static void x_draw_image_foreground P_ ((struct glyph_string *));
static void x_draw_image_foreground_1 P_ ((struct glyph_string *, Pixmap));
static void x_clear_glyph_string_rect P_ ((struct glyph_string *, int,
					   int, int, int));
static void x_draw_relief_rect P_ ((struct frame *, int, int, int, int,
				    int, int, int, int, int, int,
				    Rect *));
static void x_draw_box_rect P_ ((struct glyph_string *, int, int, int, int,
				 int, int, int, Rect *));

#if GLYPH_DEBUG
static void x_check_font P_ ((struct frame *, XFontStruct *));
#endif


/* Set S->gc to a suitable GC for drawing glyph string S in cursor
   face.  */

static void
x_set_cursor_gc (s)
     struct glyph_string *s;
{
  if (s->font == FRAME_FONT (s->f)
      && s->face->background == FRAME_BACKGROUND_PIXEL (s->f)
      && s->face->foreground == FRAME_FOREGROUND_PIXEL (s->f)
      && !s->cmp)
    s->gc = s->f->output_data.mac->cursor_gc;
  else
    {
      /* Cursor on non-default face: must merge.  */
      XGCValues xgcv;
      unsigned long mask;

      xgcv.background = s->f->output_data.mac->cursor_pixel;
      xgcv.foreground = s->face->background;

      /* If the glyph would be invisible, try a different foreground.  */
      if (xgcv.foreground == xgcv.background)
	xgcv.foreground = s->face->foreground;
      if (xgcv.foreground == xgcv.background)
	xgcv.foreground = s->f->output_data.mac->cursor_foreground_pixel;
      if (xgcv.foreground == xgcv.background)
	xgcv.foreground = s->face->foreground;

      /* Make sure the cursor is distinct from text in this face.  */
      if (xgcv.background == s->face->background
	  && xgcv.foreground == s->face->foreground)
	{
	  xgcv.background = s->face->foreground;
	  xgcv.foreground = s->face->background;
	}

      IF_DEBUG (x_check_font (s->f, s->font));
      xgcv.font = s->font;
      mask = GCForeground | GCBackground | GCFont;

      if (FRAME_MAC_DISPLAY_INFO (s->f)->scratch_cursor_gc)
	XChangeGC (s->display, FRAME_MAC_DISPLAY_INFO (s->f)->scratch_cursor_gc,
		   mask, &xgcv);
      else
	FRAME_MAC_DISPLAY_INFO (s->f)->scratch_cursor_gc
	  = XCreateGC (s->display, s->window, mask, &xgcv);

      s->gc = FRAME_MAC_DISPLAY_INFO (s->f)->scratch_cursor_gc;
    }
}


/* Set up S->gc of glyph string S for drawing text in mouse face.  */

static void
x_set_mouse_face_gc (s)
     struct glyph_string *s;
{
  int face_id;
  struct face *face;

  /* What face has to be used last for the mouse face?  */
  face_id = FRAME_X_DISPLAY_INFO (s->f)->mouse_face_face_id;
  face = FACE_FROM_ID (s->f, face_id);
  if (face == NULL)
    face = FACE_FROM_ID (s->f, MOUSE_FACE_ID);

  if (s->first_glyph->type == CHAR_GLYPH)
    face_id = FACE_FOR_CHAR (s->f, face, s->first_glyph->u.ch);
  else
    face_id = FACE_FOR_CHAR (s->f, face, 0);
  s->face = FACE_FROM_ID (s->f, face_id);
  PREPARE_FACE_FOR_DISPLAY (s->f, s->face);

  /* If font in this face is same as S->font, use it.  */
  if (s->font == s->face->font)
    s->gc = s->face->gc;
  else
    {
      /* Otherwise construct scratch_cursor_gc with values from FACE
	 but font FONT.  */
      XGCValues xgcv;
      unsigned long mask;

      xgcv.background = s->face->background;
      xgcv.foreground = s->face->foreground;
      IF_DEBUG (x_check_font (s->f, s->font));
      xgcv.font = s->font;
      mask = GCForeground | GCBackground | GCFont;

      if (FRAME_MAC_DISPLAY_INFO (s->f)->scratch_cursor_gc)
	XChangeGC (s->display, FRAME_MAC_DISPLAY_INFO (s->f)->scratch_cursor_gc,
		   mask, &xgcv);
      else
	FRAME_MAC_DISPLAY_INFO (s->f)->scratch_cursor_gc
	  = XCreateGC (s->display, s->window, mask, &xgcv);

      s->gc = FRAME_MAC_DISPLAY_INFO (s->f)->scratch_cursor_gc;
    }

  xassert (s->gc != 0);
}


/* Set S->gc of glyph string S to a GC suitable for drawing a mode line.
   Faces to use in the mode line have already been computed when the
   matrix was built, so there isn't much to do, here.  */

static INLINE void
x_set_mode_line_face_gc (s)
     struct glyph_string *s;
{
  s->gc = s->face->gc;
}


/* Set S->gc of glyph string S for drawing that glyph string.  Set
   S->stippled_p to a non-zero value if the face of S has a stipple
   pattern.  */

static INLINE void
x_set_glyph_string_gc (s)
     struct glyph_string *s;
{
  PREPARE_FACE_FOR_DISPLAY (s->f, s->face);

  if (s->hl == DRAW_NORMAL_TEXT)
    {
      s->gc = s->face->gc;
      s->stippled_p = s->face->stipple != 0;
    }
  else if (s->hl == DRAW_INVERSE_VIDEO)
    {
      x_set_mode_line_face_gc (s);
      s->stippled_p = s->face->stipple != 0;
    }
  else if (s->hl == DRAW_CURSOR)
    {
      x_set_cursor_gc (s);
      s->stippled_p = 0;
    }
  else if (s->hl == DRAW_MOUSE_FACE)
    {
      x_set_mouse_face_gc (s);
      s->stippled_p = s->face->stipple != 0;
    }
  else if (s->hl == DRAW_IMAGE_RAISED
	   || s->hl == DRAW_IMAGE_SUNKEN)
    {
      s->gc = s->face->gc;
      s->stippled_p = s->face->stipple != 0;
    }
  else
    {
      s->gc = s->face->gc;
      s->stippled_p = s->face->stipple != 0;
    }

  /* GC must have been set.  */
  xassert (s->gc != 0);
}


/* Set clipping for output of glyph string S.  S may be part of a mode
   line or menu if we don't have X toolkit support.  */

static INLINE void
x_set_glyph_string_clipping (s)
     struct glyph_string *s;
{
  Rect r;
  get_glyph_string_clip_rect (s, &r);
  mac_set_clip_rectangle (s->display, s->window, &r);
}


/* RIF:
   Compute left and right overhang of glyph string S.  If S is a glyph
   string for a composition, assume overhangs don't exist.  */

static void
mac_compute_glyph_string_overhangs (s)
     struct glyph_string *s;
{
  Rect r;
  MacFontStruct *font = s->font;

  TextFont (font->mac_fontnum);
  TextSize (font->mac_fontsize);
  TextFace (font->mac_fontface);

  if (s->two_byte_p)
    QDTextBounds (s->nchars * 2, (char *)s->char2b, &r);
  else
    {
      int i;
      char *buf = xmalloc (s->nchars);

      if (buf == NULL)
	SetRect (&r, 0, 0, 0, 0);
      else
	{
	  for (i = 0; i < s->nchars; ++i)
	    buf[i] = s->char2b[i].byte2;
	  QDTextBounds (s->nchars, buf, &r);
	  xfree (buf);
	}
    }

  s->right_overhang = r.right > s->width ? r.right - s->width : 0;
  s->left_overhang = r.left < 0 ? -r.left : 0;
}


/* Fill rectangle X, Y, W, H with background color of glyph string S.  */

static INLINE void
x_clear_glyph_string_rect (s, x, y, w, h)
     struct glyph_string *s;
     int x, y, w, h;
{
  XGCValues xgcv;

  xgcv.foreground = s->gc->background;
  XFillRectangle (s->display, s->window, &xgcv, x, y, w, h);
}


/* We prefer not to use XDrawImageString (srcCopy text transfer mode)
   on Mac OS X because:
   - Screen is double-buffered.  (In srcCopy mode, a text is drawn
     into an offscreen graphics world first.  So performance gain
     cannot be expected.)
   - It lowers rendering quality.
   - Some fonts leave garbage on cursor movement.  */

/* Draw the background of glyph_string S.  If S->background_filled_p
   is non-zero don't draw it.  FORCE_P non-zero means draw the
   background even if it wouldn't be drawn normally.  This is used
   when a string preceding S draws into the background of S, or S
   contains the first component of a composition.  */

static void
x_draw_glyph_string_background (s, force_p)
     struct glyph_string *s;
     int force_p;
{
  /* Nothing to do if background has already been drawn or if it
     shouldn't be drawn in the first place.  */
  if (!s->background_filled_p)
    {
      int box_line_width = max (s->face->box_line_width, 0);

#if 0 /* MAC_TODO: stipple */
      if (s->stippled_p)
	{
	  /* Fill background with a stipple pattern.  */
	  XSetFillStyle (s->display, s->gc, FillOpaqueStippled);
	  XFillRectangle (s->display, s->window, s->gc, s->x,
			  s->y + box_line_width,
			  s->background_width,
			  s->height - 2 * box_line_width);
	  XSetFillStyle (s->display, s->gc, FillSolid);
	  s->background_filled_p = 1;
	}
      else
#endif
#ifdef MAC_OS8
        if (FONT_HEIGHT (s->font) < s->height - 2 * box_line_width
	       || s->font_not_found_p
	       || s->extends_to_end_of_line_p
	       || force_p)
#endif
	{
	  x_clear_glyph_string_rect (s, s->x, s->y + box_line_width,
				     s->background_width,
				     s->height - 2 * box_line_width);
	  s->background_filled_p = 1;
	}
    }
}


/* Draw the foreground of glyph string S.  */

static void
x_draw_glyph_string_foreground (s)
     struct glyph_string *s;
{
  int i, x;

  /* If first glyph of S has a left box line, start drawing the text
     of S to the right of that box line.  */
  if (s->face->box != FACE_NO_BOX
      && s->first_glyph->left_box_line_p)
    x = s->x + abs (s->face->box_line_width);
  else
    x = s->x;

  /* Draw characters of S as rectangles if S's font could not be
     loaded.  */
  if (s->font_not_found_p)
    {
      for (i = 0; i < s->nchars; ++i)
	{
	  struct glyph *g = s->first_glyph + i;
	  mac_draw_rectangle (s->display, s->window,
			    s->gc, x, s->y, g->pixel_width - 1,
			    s->height - 1);
	  x += g->pixel_width;
	}
    }
  else
    {
      char *char1b = (char *) s->char2b;
      int boff = s->font_info->baseline_offset;

      if (s->font_info->vertical_centering)
	boff = VCENTER_BASELINE_OFFSET (s->font, s->f) - boff;

      /* If we can use 8-bit functions, condense S->char2b.  */
      if (!s->two_byte_p)
	for (i = 0; i < s->nchars; ++i)
	  char1b[i] = s->char2b[i].byte2;

#ifdef MAC_OS8
      /* Draw text with XDrawString if background has already been
	 filled.  Otherwise, use XDrawImageString.  (Note that
	 XDrawImageString is usually faster than XDrawString.)  Always
	 use XDrawImageString when drawing the cursor so that there is
	 no chance that characters under a box cursor are invisible.  */
      if (s->for_overlaps_p
	  || (s->background_filled_p && s->hl != DRAW_CURSOR))
#endif
	{
	  /* Draw characters with 16-bit or 8-bit functions.  */
	  if (s->two_byte_p)
	    XDrawString16 (s->display, s->window, s->gc, x,
			   s->ybase - boff, s->char2b, s->nchars);
	  else
	    XDrawString (s->display, s->window, s->gc, x,
			 s->ybase - boff, char1b, s->nchars);
	}
#ifdef MAC_OS8
      else
	{
	  if (s->two_byte_p)
	    XDrawImageString16 (s->display, s->window, s->gc, x,
			        s->ybase - boff, s->char2b, s->nchars);
	  else
	    XDrawImageString (s->display, s->window, s->gc, x,
			      s->ybase - boff, char1b, s->nchars);
	}
#endif
    }
}

/* Draw the foreground of composite glyph string S.  */

static void
x_draw_composite_glyph_string_foreground (s)
     struct glyph_string *s;
{
  int i, x;

  /* If first glyph of S has a left box line, start drawing the text
     of S to the right of that box line.  */
  if (s->face->box != FACE_NO_BOX
      && s->first_glyph->left_box_line_p)
    x = s->x + abs (s->face->box_line_width);
  else
    x = s->x;

  /* S is a glyph string for a composition.  S->gidx is the index of
     the first character drawn for glyphs of this composition.
     S->gidx == 0 means we are drawing the very first character of
     this composition.  */

  /* Draw a rectangle for the composition if the font for the very
     first character of the composition could not be loaded.  */
  if (s->font_not_found_p)
    {
      if (s->gidx == 0)
	mac_draw_rectangle (s->display, s->window, s->gc, x, s->y,
			  s->width - 1, s->height - 1);
    }
  else
    {
      for (i = 0; i < s->nchars; i++, ++s->gidx)
	XDrawString16 (s->display, s->window, s->gc,
		       x + s->cmp->offsets[s->gidx * 2],
		       s->ybase - s->cmp->offsets[s->gidx * 2 + 1],
		       s->char2b + i, 1);
    }
}


#ifdef USE_X_TOOLKIT

static struct frame *x_frame_of_widget P_ ((Widget));


/* Return the frame on which widget WIDGET is used.. Abort if frame
   cannot be determined.  */

static struct frame *
x_frame_of_widget (widget)
     Widget widget;
{
  struct x_display_info *dpyinfo;
  Lisp_Object tail;
  struct frame *f;

  dpyinfo = x_display_info_for_display (XtDisplay (widget));

  /* Find the top-level shell of the widget.  Note that this function
     can be called when the widget is not yet realized, so XtWindow
     (widget) == 0.  That's the reason we can't simply use
     x_any_window_to_frame.  */
  while (!XtIsTopLevelShell (widget))
    widget = XtParent (widget);

  /* Look for a frame with that top-level widget.  Allocate the color
     on that frame to get the right gamma correction value.  */
  for (tail = Vframe_list; GC_CONSP (tail); tail = XCDR (tail))
    if (GC_FRAMEP (XCAR (tail))
	&& (f = XFRAME (XCAR (tail)),
	    (f->output_data.nothing != 1
	     && FRAME_X_DISPLAY_INFO (f) == dpyinfo))
	&& f->output_data.x->widget == widget)
      return f;

  abort ();
}


/* Allocate the color COLOR->pixel on the screen and display of
   widget WIDGET in colormap CMAP.  If an exact match cannot be
   allocated, try the nearest color available.  Value is non-zero
   if successful.  This is called from lwlib.  */

int
x_alloc_nearest_color_for_widget (widget, cmap, color)
     Widget widget;
     Colormap cmap;
     XColor *color;
{
  struct frame *f = x_frame_of_widget (widget);
  return x_alloc_nearest_color (f, cmap, color);
}


#endif /* USE_X_TOOLKIT */

#if 0 /* MAC_TODO */

/* Allocate the color COLOR->pixel on SCREEN of DISPLAY, colormap
   CMAP.  If an exact match can't be allocated, try the nearest color
   available.  Value is non-zero if successful.  Set *COLOR to the
   color allocated.  */

int
x_alloc_nearest_color (f, cmap, color)
     struct frame *f;
     Colormap cmap;
     XColor *color;
{
  Display *display = FRAME_X_DISPLAY (f);
  Screen *screen = FRAME_X_SCREEN (f);
  int rc;

  gamma_correct (f, color);
  rc = XAllocColor (display, cmap, color);
  if (rc == 0)
    {
      /* If we got to this point, the colormap is full, so we're going
	 to try to get the next closest color.  The algorithm used is
	 a least-squares matching, which is what X uses for closest
	 color matching with StaticColor visuals.  */
      int nearest, i;
      unsigned long nearest_delta = ~0;
      int ncells = XDisplayCells (display, XScreenNumberOfScreen (screen));
      XColor *cells = (XColor *) alloca (ncells * sizeof *cells);

      for (i = 0; i < ncells; ++i)
	cells[i].pixel = i;
      XQueryColors (display, cmap, cells, ncells);

      for (nearest = i = 0; i < ncells; ++i)
	{
	  long dred   = (color->red   >> 8) - (cells[i].red   >> 8);
	  long dgreen = (color->green >> 8) - (cells[i].green >> 8);
	  long dblue  = (color->blue  >> 8) - (cells[i].blue  >> 8);
	  unsigned long delta = dred * dred + dgreen * dgreen + dblue * dblue;

	  if (delta < nearest_delta)
	    {
	      nearest = i;
	      nearest_delta = delta;
	    }
	}

      color->red   = cells[nearest].red;
      color->green = cells[nearest].green;
      color->blue  = cells[nearest].blue;
      rc = XAllocColor (display, cmap, color);
    }

#ifdef DEBUG_X_COLORS
  if (rc)
    register_color (color->pixel);
#endif /* DEBUG_X_COLORS */

  return rc;
}


/* Allocate color PIXEL on frame F.  PIXEL must already be allocated.
   It's necessary to do this instead of just using PIXEL directly to
   get color reference counts right.  */

unsigned long
x_copy_color (f, pixel)
     struct frame *f;
     unsigned long pixel;
{
  XColor color;

  color.pixel = pixel;
  BLOCK_INPUT;
  XQueryColor (FRAME_X_DISPLAY (f), FRAME_X_COLORMAP (f), &color);
  XAllocColor (FRAME_X_DISPLAY (f), FRAME_X_COLORMAP (f), &color);
  UNBLOCK_INPUT;
#ifdef DEBUG_X_COLORS
  register_color (pixel);
#endif
  return color.pixel;
}


/* Allocate color PIXEL on display DPY.  PIXEL must already be allocated.
   It's necessary to do this instead of just using PIXEL directly to
   get color reference counts right.  */

unsigned long
x_copy_dpy_color (dpy, cmap, pixel)
     Display *dpy;
     Colormap cmap;
     unsigned long pixel;
{
  XColor color;

  color.pixel = pixel;
  BLOCK_INPUT;
  XQueryColor (dpy, cmap, &color);
  XAllocColor (dpy, cmap, &color);
  UNBLOCK_INPUT;
#ifdef DEBUG_X_COLORS
  register_color (pixel);
#endif
  return color.pixel;
}

#endif /* MAC_TODO */


/* Brightness beyond which a color won't have its highlight brightness
   boosted.

   Nominally, highlight colors for `3d' faces are calculated by
   brightening an object's color by a constant scale factor, but this
   doesn't yield good results for dark colors, so for colors who's
   brightness is less than this value (on a scale of 0-255) have to
   use an additional additive factor.

   The value here is set so that the default menu-bar/mode-line color
   (grey75) will not have its highlights changed at all.  */
#define HIGHLIGHT_COLOR_DARK_BOOST_LIMIT 187


/* Allocate a color which is lighter or darker than *COLOR by FACTOR
   or DELTA.  Try a color with RGB values multiplied by FACTOR first.
   If this produces the same color as COLOR, try a color where all RGB
   values have DELTA added.  Return the allocated color in *COLOR.
   DISPLAY is the X display, CMAP is the colormap to operate on.
   Value is non-zero if successful.  */

static int
mac_alloc_lighter_color (f, color, factor, delta)
     struct frame *f;
     unsigned long *color;
     double factor;
     int delta;
{
  unsigned long new;
  long bright;

  /* On Mac, RGB values are 0-255, not 0-65535, so scale delta. */
  delta /= 256;

  /* Change RGB values by specified FACTOR.  Avoid overflow!  */
  xassert (factor >= 0);
  new = RGB_TO_ULONG (min (0xff, (int) (factor * RED_FROM_ULONG (*color))),
                    min (0xff, (int) (factor * GREEN_FROM_ULONG (*color))),
                    min (0xff, (int) (factor * BLUE_FROM_ULONG (*color))));

  /* Calculate brightness of COLOR.  */
  bright = (2 * RED_FROM_ULONG (*color) + 3 * GREEN_FROM_ULONG (*color)
            + BLUE_FROM_ULONG (*color)) / 6;

  /* We only boost colors that are darker than
     HIGHLIGHT_COLOR_DARK_BOOST_LIMIT.  */
  if (bright < HIGHLIGHT_COLOR_DARK_BOOST_LIMIT)
    /* Make an additive adjustment to NEW, because it's dark enough so
       that scaling by FACTOR alone isn't enough.  */
    {
      /* How far below the limit this color is (0 - 1, 1 being darker).  */
      double dimness = 1 - (double)bright / HIGHLIGHT_COLOR_DARK_BOOST_LIMIT;
      /* The additive adjustment.  */
      int min_delta = delta * dimness * factor / 2;

      if (factor < 1)
        new = RGB_TO_ULONG (max (0, min (0xff, (int) (RED_FROM_ULONG (*color)) - min_delta)),
			    max (0, min (0xff, (int) (GREEN_FROM_ULONG (*color)) - min_delta)),
			    max (0, min (0xff, (int) (BLUE_FROM_ULONG (*color)) - min_delta)));
      else
        new = RGB_TO_ULONG (max (0, min (0xff, (int) (min_delta + RED_FROM_ULONG (*color)))),
			    max (0, min (0xff, (int) (min_delta + GREEN_FROM_ULONG (*color)))),
			    max (0, min (0xff, (int) (min_delta + BLUE_FROM_ULONG (*color)))));
    }

  if (new == *color)
    new = RGB_TO_ULONG (max (0, min (0xff, (int) (delta + RED_FROM_ULONG (*color)))),
                      max (0, min (0xff, (int) (delta + GREEN_FROM_ULONG (*color)))),
                      max (0, min (0xff, (int) (delta + BLUE_FROM_ULONG (*color)))));

  /* MAC_TODO: Map to palette and retry with delta if same? */
  /* MAC_TODO: Free colors (if using palette)? */

  if (new == *color)
    return 0;

  *color = new;

  return 1;
}


/* Set up the foreground color for drawing relief lines of glyph
   string S.  RELIEF is a pointer to a struct relief containing the GC
   with which lines will be drawn.  Use a color that is FACTOR or
   DELTA lighter or darker than the relief's background which is found
   in S->f->output_data.x->relief_background.  If such a color cannot
   be allocated, use DEFAULT_PIXEL, instead.  */

static void
x_setup_relief_color (f, relief, factor, delta, default_pixel)
     struct frame *f;
     struct relief *relief;
     double factor;
     int delta;
     unsigned long default_pixel;
{
  XGCValues xgcv;
  struct mac_output *di = f->output_data.mac;
  unsigned long mask = GCForeground;
  unsigned long pixel;
  unsigned long background = di->relief_background;
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (f);

  /* MAC_TODO: Free colors (if using palette)? */

  /* Allocate new color.  */
  xgcv.foreground = default_pixel;
  pixel = background;
  if (dpyinfo->n_planes != 1
      && mac_alloc_lighter_color (f, &pixel, factor, delta))
    {
      relief->allocated_p = 1;
      xgcv.foreground = relief->pixel = pixel;
    }

  if (relief->gc == 0)
    {
#if 0 /* MAC_TODO: stipple */
      xgcv.stipple = dpyinfo->gray;
      mask |= GCStipple;
#endif
      relief->gc = XCreateGC (NULL, FRAME_MAC_WINDOW (f), mask, &xgcv);
    }
  else
    XChangeGC (NULL, relief->gc, mask, &xgcv);
}


/* Set up colors for the relief lines around glyph string S.  */

static void
x_setup_relief_colors (s)
     struct glyph_string *s;
{
  struct mac_output *di = s->f->output_data.mac;
  unsigned long color;

  if (s->face->use_box_color_for_shadows_p)
    color = s->face->box_color;
  else if (s->first_glyph->type == IMAGE_GLYPH
	   && s->img->pixmap
	   && !IMAGE_BACKGROUND_TRANSPARENT (s->img, s->f, 0))
    color = IMAGE_BACKGROUND (s->img, s->f, 0);
  else
    {
      XGCValues xgcv;

      /* Get the background color of the face.  */
      XGetGCValues (s->display, s->gc, GCBackground, &xgcv);
      color = xgcv.background;
    }

  if (di->white_relief.gc == 0
      || color != di->relief_background)
    {
      di->relief_background = color;
      x_setup_relief_color (s->f, &di->white_relief, 1.2, 0x8000,
			    WHITE_PIX_DEFAULT (s->f));
      x_setup_relief_color (s->f, &di->black_relief, 0.6, 0x4000,
			    BLACK_PIX_DEFAULT (s->f));
    }
}


/* Draw a relief on frame F inside the rectangle given by LEFT_X,
   TOP_Y, RIGHT_X, and BOTTOM_Y.  WIDTH is the thickness of the relief
   to draw, it must be >= 0.  RAISED_P non-zero means draw a raised
   relief.  LEFT_P non-zero means draw a relief on the left side of
   the rectangle.  RIGHT_P non-zero means draw a relief on the right
   side of the rectangle.  CLIP_RECT is the clipping rectangle to use
   when drawing.  */

static void
x_draw_relief_rect (f, left_x, top_y, right_x, bottom_y, width,
		    raised_p, top_p, bot_p, left_p, right_p, clip_rect)
     struct frame *f;
     int left_x, top_y, right_x, bottom_y, width;
     int top_p, bot_p, left_p, right_p, raised_p;
     Rect *clip_rect;
{
  Display *dpy = FRAME_MAC_DISPLAY (f);
  Window window = FRAME_MAC_WINDOW (f);
  int i;
  GC gc;

  if (raised_p)
    gc = f->output_data.mac->white_relief.gc;
  else
    gc = f->output_data.mac->black_relief.gc;
  mac_set_clip_rectangle (dpy, window, clip_rect);

  /* Top.  */
  if (top_p)
    for (i = 0; i < width; ++i)
      XDrawLine (dpy, window, gc,
		 left_x + i * left_p, top_y + i,
		 right_x - i * right_p, top_y + i);

  /* Left.  */
  if (left_p)
    for (i = 0; i < width; ++i)
      XDrawLine (dpy, window, gc,
		 left_x + i, top_y + i, left_x + i, bottom_y - i);

  mac_reset_clipping (dpy, window);
  if (raised_p)
    gc = f->output_data.mac->black_relief.gc;
  else
    gc = f->output_data.mac->white_relief.gc;
  mac_set_clip_rectangle (dpy, window,
			  clip_rect);

  /* Bottom.  */
  if (bot_p)
    for (i = 0; i < width; ++i)
      XDrawLine (dpy, window, gc,
		 left_x + i * left_p, bottom_y - i,
		 right_x - i * right_p, bottom_y - i);

  /* Right.  */
  if (right_p)
    for (i = 0; i < width; ++i)
      XDrawLine (dpy, window, gc,
		 right_x - i, top_y + i + 1, right_x - i, bottom_y - i - 1);

  mac_reset_clipping (dpy, window);
}


/* Draw a box on frame F inside the rectangle given by LEFT_X, TOP_Y,
   RIGHT_X, and BOTTOM_Y.  WIDTH is the thickness of the lines to
   draw, it must be >= 0.  LEFT_P non-zero means draw a line on the
   left side of the rectangle.  RIGHT_P non-zero means draw a line
   on the right side of the rectangle.  CLIP_RECT is the clipping
   rectangle to use when drawing.  */

static void
x_draw_box_rect (s, left_x, top_y, right_x, bottom_y, width,
		 left_p, right_p, clip_rect)
     struct glyph_string *s;
     int left_x, top_y, right_x, bottom_y, width, left_p, right_p;
     Rect *clip_rect;
{
  XGCValues xgcv;

  xgcv.foreground = s->face->box_color;
  mac_set_clip_rectangle (s->display, s->window, clip_rect);

  /* Top.  */
  XFillRectangle (s->display, s->window, &xgcv,
		  left_x, top_y, right_x - left_x + 1, width);

  /* Left.  */
  if (left_p)
    XFillRectangle (s->display, s->window, &xgcv,
		    left_x, top_y, width, bottom_y - top_y + 1);

  /* Bottom.  */
  XFillRectangle (s->display, s->window, &xgcv,
		  left_x, bottom_y - width + 1, right_x - left_x + 1, width);

  /* Right.  */
  if (right_p)
    XFillRectangle (s->display, s->window, &xgcv,
		    right_x - width + 1, top_y, width, bottom_y - top_y + 1);

  mac_reset_clipping (s->display, s->window);
}


/* Draw a box around glyph string S.  */

static void
x_draw_glyph_string_box (s)
     struct glyph_string *s;
{
  int width, left_x, right_x, top_y, bottom_y, last_x, raised_p;
  int left_p, right_p;
  struct glyph *last_glyph;
  Rect clip_rect;

  last_x = ((s->row->full_width_p && !s->w->pseudo_window_p)
	    ? WINDOW_RIGHT_EDGE_X (s->w)
	    : window_box_right (s->w, s->area));

  /* The glyph that may have a right box line.  */
  last_glyph = (s->cmp || s->img
		? s->first_glyph
		: s->first_glyph + s->nchars - 1);

  width = abs (s->face->box_line_width);
  raised_p = s->face->box == FACE_RAISED_BOX;
  left_x = s->x;
  right_x = (s->row->full_width_p && s->extends_to_end_of_line_p
	     ? last_x - 1
	     : min (last_x, s->x + s->background_width) - 1);
  top_y = s->y;
  bottom_y = top_y + s->height - 1;

  left_p = (s->first_glyph->left_box_line_p
	    || (s->hl == DRAW_MOUSE_FACE
		&& (s->prev == NULL
		    || s->prev->hl != s->hl)));
  right_p = (last_glyph->right_box_line_p
	     || (s->hl == DRAW_MOUSE_FACE
		 && (s->next == NULL
		     || s->next->hl != s->hl)));

  get_glyph_string_clip_rect (s, &clip_rect);

  if (s->face->box == FACE_SIMPLE_BOX)
    x_draw_box_rect (s, left_x, top_y, right_x, bottom_y, width,
		     left_p, right_p, &clip_rect);
  else
    {
      x_setup_relief_colors (s);
      x_draw_relief_rect (s->f, left_x, top_y, right_x, bottom_y,
			  width, raised_p, 1, 1, left_p, right_p, &clip_rect);
    }
}


/* Draw foreground of image glyph string S.  */

static void
x_draw_image_foreground (s)
     struct glyph_string *s;
{
  int x = s->x;
  int y = s->ybase - image_ascent (s->img, s->face, &s->slice);

  /* If first glyph of S has a left box line, start drawing it to the
     right of that line.  */
  if (s->face->box != FACE_NO_BOX
      && s->first_glyph->left_box_line_p
      && s->slice.x == 0)
    x += abs (s->face->box_line_width);

  /* If there is a margin around the image, adjust x- and y-position
     by that margin.  */
  if (s->slice.x == 0)
    x += s->img->hmargin;
  if (s->slice.y == 0)
    y += s->img->vmargin;

  if (s->img->pixmap)
    {
      x_set_glyph_string_clipping (s);

      if (s->img->mask)
	mac_copy_area_with_mask (s->display, s->img->pixmap, s->img->mask,
				 s->window, s->gc, s->slice.x, s->slice.y,
				 s->slice.width, s->slice.height, x, y);
      else
	{
	  mac_copy_area (s->display, s->img->pixmap,
			 s->window, s->gc, s->slice.x, s->slice.y,
			 s->slice.width, s->slice.height, x, y);

	  /* When the image has a mask, we can expect that at
	     least part of a mouse highlight or a block cursor will
	     be visible.  If the image doesn't have a mask, make
	     a block cursor visible by drawing a rectangle around
	     the image.  I believe it's looking better if we do
	     nothing here for mouse-face.  */
	  if (s->hl == DRAW_CURSOR)
	    {
	      int r = s->img->relief;
	      if (r < 0) r = -r;
	      mac_draw_rectangle (s->display, s->window, s->gc,
				  x - r, y - r,
				  s->slice.width + r*2 - 1,
				  s->slice.height + r*2 - 1);
	    }
	}
    }
  else
    /* Draw a rectangle if image could not be loaded.  */
    mac_draw_rectangle (s->display, s->window, s->gc, x, y,
			s->slice.width - 1, s->slice.height - 1);
}


/* Draw a relief around the image glyph string S.  */

static void
x_draw_image_relief (s)
     struct glyph_string *s;
{
  int x0, y0, x1, y1, thick, raised_p;
  Rect r;
  int x = s->x;
  int y = s->ybase - image_ascent (s->img, s->face, &s->slice);

  /* If first glyph of S has a left box line, start drawing it to the
     right of that line.  */
  if (s->face->box != FACE_NO_BOX
      && s->first_glyph->left_box_line_p
      && s->slice.x == 0)
    x += abs (s->face->box_line_width);

  /* If there is a margin around the image, adjust x- and y-position
     by that margin.  */
  if (s->slice.x == 0)
    x += s->img->hmargin;
  if (s->slice.y == 0)
    y += s->img->vmargin;

  if (s->hl == DRAW_IMAGE_SUNKEN
      || s->hl == DRAW_IMAGE_RAISED)
    {
      thick = tool_bar_button_relief >= 0 ? tool_bar_button_relief : DEFAULT_TOOL_BAR_BUTTON_RELIEF;
      raised_p = s->hl == DRAW_IMAGE_RAISED;
    }
  else
    {
      thick = abs (s->img->relief);
      raised_p = s->img->relief > 0;
    }

  x0 = x - thick;
  y0 = y - thick;
  x1 = x + s->slice.width + thick - 1;
  y1 = y + s->slice.height + thick - 1;

  x_setup_relief_colors (s);
  get_glyph_string_clip_rect (s, &r);
  x_draw_relief_rect (s->f, x0, y0, x1, y1, thick, raised_p,
		      s->slice.y == 0,
		      s->slice.y + s->slice.height == s->img->height,
		      s->slice.x == 0,
		      s->slice.x + s->slice.width == s->img->width,
		      &r);
}


#if 0 /* TODO: figure out if we need to do this on Mac.  */
/* Draw the foreground of image glyph string S to PIXMAP.  */

static void
x_draw_image_foreground_1 (s, pixmap)
     struct glyph_string *s;
     Pixmap pixmap;
{
  int x = 0;
  int y = s->ybase - s->y - image_ascent (s->img, s->face, &s->slice);

  /* If first glyph of S has a left box line, start drawing it to the
     right of that line.  */
  if (s->face->box != FACE_NO_BOX
      && s->first_glyph->left_box_line_p
      && s->slice.x == 0)
    x += abs (s->face->box_line_width);

  /* If there is a margin around the image, adjust x- and y-position
     by that margin.  */
  if (s->slice.x == 0)
    x += s->img->hmargin;
  if (s->slice.y == 0)
    y += s->img->vmargin;

  if (s->img->pixmap)
    {
      if (s->img->mask)
	mac_copy_area_with_mask_to_pixmap (s->display, s->img->pixmap,
					   s->img->mask, pixmap, s->gc,
					   s->slice.x, s->slice.y,
					   s->slice.width, s->slice.height,
					   x, y);
      else
	{
	  mac_copy_area_to_pixmap (s->display, s->img->pixmap, pixmap, s->gc,
				   s->slice.x, s->slice.y,
				   s->slice.width, s->slice.height,
				   x, y);

	  /* When the image has a mask, we can expect that at
	     least part of a mouse highlight or a block cursor will
	     be visible.  If the image doesn't have a mask, make
	     a block cursor visible by drawing a rectangle around
	     the image.  I believe it's looking better if we do
	     nothing here for mouse-face.  */
	  if (s->hl == DRAW_CURSOR)
	    {
	      int r = s->img->relief;
	      if (r < 0) r = -r;
	      mac_draw_rectangle (s->display, s->window, s->gc, x - r, y - r,
				  s->slice.width + r*2 - 1,
				  s->slice.height + r*2 - 1);
	    }
	}
    }
  else
    /* Draw a rectangle if image could not be loaded.  */
    mac_draw_rectangle_to_pixmap (s->display, pixmap, s->gc, x, y,
				  s->slice.width - 1, s->slice.height - 1);
}
#endif


/* Draw part of the background of glyph string S.  X, Y, W, and H
   give the rectangle to draw.  */

static void
x_draw_glyph_string_bg_rect (s, x, y, w, h)
     struct glyph_string *s;
     int x, y, w, h;
{
#if 0 /* MAC_TODO: stipple */
  if (s->stippled_p)
    {
      /* Fill background with a stipple pattern.  */
      XSetFillStyle (s->display, s->gc, FillOpaqueStippled);
      XFillRectangle (s->display, s->window, s->gc, x, y, w, h);
      XSetFillStyle (s->display, s->gc, FillSolid);
    }
  else
#endif /* MAC_TODO */
    x_clear_glyph_string_rect (s, x, y, w, h);
}


/* Draw image glyph string S.

            s->y
   s->x      +-------------------------
	     |   s->face->box
	     |
	     |     +-------------------------
	     |     |  s->img->margin
	     |     |
	     |     |       +-------------------
	     |     |       |  the image

 */

static void
x_draw_image_glyph_string (s)
     struct glyph_string *s;
{
  int x, y;
  int box_line_hwidth = abs (s->face->box_line_width);
  int box_line_vwidth = max (s->face->box_line_width, 0);
  int height;
  Pixmap pixmap = 0;

  height = s->height - 2 * box_line_vwidth;


  /* Fill background with face under the image.  Do it only if row is
     taller than image or if image has a clip mask to reduce
     flickering.  */
  s->stippled_p = s->face->stipple != 0;
  if (height > s->slice.height
      || s->img->hmargin
      || s->img->vmargin
      || s->img->mask
      || s->img->pixmap == 0
      || s->width != s->background_width)
    {
      x = s->x;
      if (s->first_glyph->left_box_line_p
	  && s->slice.x == 0)
	x += box_line_hwidth;

      y = s->y;
      if (s->slice.y == 0)
	y += box_line_vwidth;

#if 0 /* TODO: figure out if we need to do this on Mac.  */
      if (s->img->mask)
	{
	  /* Create a pixmap as large as the glyph string.  Fill it
	     with the background color.  Copy the image to it, using
	     its mask.  Copy the temporary pixmap to the display.  */
	  int depth = one_mac_display_info.n_planes;

	  /* Create a pixmap as large as the glyph string.  */
 	  pixmap = XCreatePixmap (s->display, s->window,
				  s->background_width,
				  s->height, depth);

	  /* Fill the pixmap with the background color/stipple.  */
#if 0 /* TODO: stipple */
	  if (s->stippled_p)
	    {
	      /* Fill background with a stipple pattern.  */
	      XSetFillStyle (s->display, s->gc, FillOpaqueStippled);
	      XFillRectangle (s->display, pixmap, s->gc,
			      0, 0, s->background_width, s->height);
	      XSetFillStyle (s->display, s->gc, FillSolid);
	    }
	  else
#endif
	    {
	      XGCValues xgcv;
	      XGetGCValues (s->display, s->gc, GCForeground | GCBackground,
			    &xgcv);
	      XSetForeground (s->display, s->gc, xgcv.background);
	      mac_fill_rectangle_to_pixmap (s->display, pixmap, s->gc,
					    0, 0, s->background_width,
					    s->height);
	      XSetForeground (s->display, s->gc, xgcv.foreground);
	    }
	}
      else
#endif
	x_draw_glyph_string_bg_rect (s, x, y, s->background_width, height);

      s->background_filled_p = 1;
    }

  /* Draw the foreground.  */
#if 0 /* TODO: figure out if we need to do this on Mac.  */
  if (pixmap != 0)
    {
      x_draw_image_foreground_1 (s, pixmap);
      x_set_glyph_string_clipping (s);
      mac_copy_area (s->display, pixmap, s->window, s->gc,
		     0, 0, s->background_width, s->height, s->x, s->y);
      mac_reset_clipping (s->display, s->window);
      XFreePixmap (s->display, pixmap);
    }
  else
#endif
    x_draw_image_foreground (s);

  /* If we must draw a relief around the image, do it.  */
  if (s->img->relief
      || s->hl == DRAW_IMAGE_RAISED
      || s->hl == DRAW_IMAGE_SUNKEN)
    x_draw_image_relief (s);
}


/* Draw stretch glyph string S.  */

static void
x_draw_stretch_glyph_string (s)
     struct glyph_string *s;
{
  xassert (s->first_glyph->type == STRETCH_GLYPH);
  s->stippled_p = s->face->stipple != 0;

  if (s->hl == DRAW_CURSOR
      && !x_stretch_cursor_p)
    {
      /* If `x-stretch-block-cursor' is nil, don't draw a block cursor
	 as wide as the stretch glyph.  */
      int width = min (FRAME_COLUMN_WIDTH (s->f), s->background_width);

      /* Draw cursor.  */
      x_draw_glyph_string_bg_rect (s, s->x, s->y, width, s->height);

      /* Clear rest using the GC of the original non-cursor face.  */
      if (width < s->background_width)
	{
	  int x = s->x + width, y = s->y;
	  int w = s->background_width - width, h = s->height;
	  Rect r;
	  GC gc;

	  if (s->row->mouse_face_p
	      && cursor_in_mouse_face_p (s->w))
	    {
	      x_set_mouse_face_gc (s);
	      gc = s->gc;
	    }
	  else
	    gc = s->face->gc;

	  get_glyph_string_clip_rect (s, &r);
	  mac_set_clip_rectangle (s->display, s->window, &r);

#if 0 /* MAC_TODO: stipple */
	  if (s->face->stipple)
	    {
	      /* Fill background with a stipple pattern.  */
	      XSetFillStyle (s->display, gc, FillOpaqueStippled);
	      XFillRectangle (s->display, s->window, gc, x, y, w, h);
	      XSetFillStyle (s->display, gc, FillSolid);
	    }
	  else
#endif /* MAC_TODO */
	    {
	      XGCValues xgcv;
	      XGetGCValues (s->display, gc, GCForeground | GCBackground, &xgcv);
	      XSetForeground (s->display, gc, xgcv.background);
	      XFillRectangle (s->display, s->window, gc, x, y, w, h);
	      XSetForeground (s->display, gc, xgcv.foreground);
	    }

	  mac_reset_clipping (s->display, s->window);
	}
    }
  else if (!s->background_filled_p)
    x_draw_glyph_string_bg_rect (s, s->x, s->y, s->background_width,
				 s->height);

  s->background_filled_p = 1;
}


/* Draw glyph string S.  */

static void
x_draw_glyph_string (s)
     struct glyph_string *s;
{
  int relief_drawn_p = 0;

  /* If S draws into the background of its successor that does not
     draw a cursor, draw the background of the successor first so that
     S can draw into it.  This makes S->next use XDrawString instead
     of XDrawImageString.  */
  if (s->next && s->right_overhang && !s->for_overlaps_p
      && s->next->hl != DRAW_CURSOR)
    {
      xassert (s->next->img == NULL);
      x_set_glyph_string_gc (s->next);
      x_set_glyph_string_clipping (s->next);
      x_draw_glyph_string_background (s->next, 1);
    }

  /* Set up S->gc, set clipping and draw S.  */
  x_set_glyph_string_gc (s);

  /* Draw relief (if any) in advance for char/composition so that the
     glyph string can be drawn over it.  */
  if (!s->for_overlaps_p
      && s->face->box != FACE_NO_BOX
      && (s->first_glyph->type == CHAR_GLYPH
	  || s->first_glyph->type == COMPOSITE_GLYPH))

    {
      x_set_glyph_string_clipping (s);
      x_draw_glyph_string_background (s, 1);
      x_draw_glyph_string_box (s);
      x_set_glyph_string_clipping (s);
      relief_drawn_p = 1;
    }
  else
    x_set_glyph_string_clipping (s);

  switch (s->first_glyph->type)
    {
    case IMAGE_GLYPH:
      x_draw_image_glyph_string (s);
      break;

    case STRETCH_GLYPH:
      x_draw_stretch_glyph_string (s);
      break;

    case CHAR_GLYPH:
      if (s->for_overlaps_p)
	s->background_filled_p = 1;
      else
	x_draw_glyph_string_background (s, 0);
      x_draw_glyph_string_foreground (s);
      break;

    case COMPOSITE_GLYPH:
      if (s->for_overlaps_p || s->gidx > 0)
	s->background_filled_p = 1;
      else
	x_draw_glyph_string_background (s, 1);
      x_draw_composite_glyph_string_foreground (s);
      break;

    default:
      abort ();
    }

  if (!s->for_overlaps_p)
    {
      /* Draw underline.  */
      if (s->face->underline_p)
	{
          unsigned long h = 1;
          unsigned long dy = s->height - h;

	  if (s->face->underline_defaulted_p)
	    XFillRectangle (s->display, s->window, s->gc, s->x, s->y + dy,
			    s->width, h);
	  else
	    {
	      XGCValues xgcv;
	      XGetGCValues (s->display, s->gc, GCForeground, &xgcv);
	      XSetForeground (s->display, s->gc, s->face->underline_color);
	      XFillRectangle (s->display, s->window, s->gc, s->x, s->y + dy,
			      s->width, h);
	      XSetForeground (s->display, s->gc, xgcv.foreground);
	    }
	}

      /* Draw overline.  */
      if (s->face->overline_p)
	{
	  unsigned long dy = 0, h = 1;

	  if (s->face->overline_color_defaulted_p)
	    XFillRectangle (s->display, s->window, s->gc, s->x, s->y + dy,
			    s->width, h);
	  else
	    {
	      XGCValues xgcv;
	      XGetGCValues (s->display, s->gc, GCForeground, &xgcv);
	      XSetForeground (s->display, s->gc, s->face->overline_color);
	      XFillRectangle (s->display, s->window, s->gc, s->x, s->y + dy,
			      s->width, h);
	      XSetForeground (s->display, s->gc, xgcv.foreground);
	    }
	}

      /* Draw strike-through.  */
      if (s->face->strike_through_p)
	{
	  unsigned long h = 1;
	  unsigned long dy = (s->height - h) / 2;

	  if (s->face->strike_through_color_defaulted_p)
	    XFillRectangle (s->display, s->window, s->gc, s->x, s->y + dy,
			    s->width, h);
	  else
	    {
	      XGCValues xgcv;
	      XGetGCValues (s->display, s->gc, GCForeground, &xgcv);
	      XSetForeground (s->display, s->gc, s->face->strike_through_color);
	      XFillRectangle (s->display, s->window, s->gc, s->x, s->y + dy,
			      s->width, h);
	      XSetForeground (s->display, s->gc, xgcv.foreground);
	    }
	}

      /* Draw relief if not yet drawn.  */
      if (!relief_drawn_p && s->face->box != FACE_NO_BOX)
	x_draw_glyph_string_box (s);
    }

  /* Reset clipping.  */
  mac_reset_clipping (s->display, s->window);
}

/* Shift display to make room for inserted glyphs.   */

void
mac_shift_glyphs_for_insert (f, x, y, width, height, shift_by)
     struct frame *f;
     int x, y, width, height, shift_by;
{
  mac_scroll_area (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
		   f->output_data.mac->normal_gc,
		   x, y, width, height,
		   x + shift_by, y);
}

/* Delete N glyphs at the nominal cursor position.  Not implemented
   for X frames.  */

static void
x_delete_glyphs (n)
     register int n;
{
  abort ();
}


/* Clear entire frame.  If updating_frame is non-null, clear that
   frame.  Otherwise clear the selected frame.  */

static void
x_clear_frame ()
{
  struct frame *f;

  if (updating_frame)
    f = updating_frame;
  else
    f = SELECTED_FRAME ();

  /* Clearing the frame will erase any cursor, so mark them all as no
     longer visible.  */
  mark_window_cursors_off (XWINDOW (FRAME_ROOT_WINDOW (f)));
  output_cursor.hpos = output_cursor.vpos = 0;
  output_cursor.x = -1;

  /* We don't set the output cursor here because there will always
     follow an explicit cursor_to.  */
  BLOCK_INPUT;
  XClearWindow (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f));

#if 0  /* Clearing frame on Mac OS clears scroll bars.  */
  /* We have to clear the scroll bars, too.  If we have changed
     colors or something like that, then they should be notified.  */
  x_scroll_bar_clear (f);
#endif

  XFlush (FRAME_MAC_DISPLAY (f));
  UNBLOCK_INPUT;
}



/* Invert the middle quarter of the frame for .15 sec.  */

/* We use the select system call to do the waiting, so we have to make
   sure it's available.  If it isn't, we just won't do visual bells.  */

#if defined (HAVE_TIMEVAL) && defined (HAVE_SELECT)


/* Subtract the `struct timeval' values X and Y, storing the result in
   *RESULT.  Return 1 if the difference is negative, otherwise 0.  */

static int
timeval_subtract (result, x, y)
     struct timeval *result, x, y;
{
  /* Perform the carry for the later subtraction by updating y.  This
     is safer because on some systems the tv_sec member is unsigned.  */
  if (x.tv_usec < y.tv_usec)
    {
      int nsec = (y.tv_usec - x.tv_usec) / 1000000 + 1;
      y.tv_usec -= 1000000 * nsec;
      y.tv_sec += nsec;
    }

  if (x.tv_usec - y.tv_usec > 1000000)
    {
      int nsec = (y.tv_usec - x.tv_usec) / 1000000;
      y.tv_usec += 1000000 * nsec;
      y.tv_sec -= nsec;
    }

  /* Compute the time remaining to wait.  tv_usec is certainly
     positive.  */
  result->tv_sec = x.tv_sec - y.tv_sec;
  result->tv_usec = x.tv_usec - y.tv_usec;

  /* Return indication of whether the result should be considered
     negative.  */
  return x.tv_sec < y.tv_sec;
}

void
XTflash (f)
     struct frame *f;
{
  BLOCK_INPUT;

  FlashMenuBar (0);

  {
    struct timeval wakeup;

    EMACS_GET_TIME (wakeup);

    /* Compute time to wait until, propagating carry from usecs.  */
    wakeup.tv_usec += 150000;
    wakeup.tv_sec += (wakeup.tv_usec / 1000000);
    wakeup.tv_usec %= 1000000;

    /* Keep waiting until past the time wakeup.  */
    while (1)
      {
        struct timeval timeout;

        EMACS_GET_TIME (timeout);

        /* In effect, timeout = wakeup - timeout.
           Break if result would be negative.  */
        if (timeval_subtract (&timeout, wakeup, timeout))
          break;

        /* Try to wait that long--but we might wake up sooner.  */
        select (0, NULL, NULL, NULL, &timeout);
      }
  }

  FlashMenuBar (0);

  UNBLOCK_INPUT;
}

#endif /* defined (HAVE_TIMEVAL) && defined (HAVE_SELECT) */


/* Make audible bell.  */

void
XTring_bell ()
{
  struct frame *f = SELECTED_FRAME ();

#if defined (HAVE_TIMEVAL) && defined (HAVE_SELECT)
  if (visible_bell)
    XTflash (f);
  else
#endif
    {
      BLOCK_INPUT;
      SysBeep (1);
      XFlush (FRAME_MAC_DISPLAY (f));
      UNBLOCK_INPUT;
    }
}



/* Specify how many text lines, from the top of the window,
   should be affected by insert-lines and delete-lines operations.
   This, and those operations, are used only within an update
   that is bounded by calls to x_update_begin and x_update_end.  */

static void
XTset_terminal_window (n)
     register int n;
{
  /* This function intentionally left blank.  */
}



/***********************************************************************
			      Line Dance
 ***********************************************************************/

/* Perform an insert-lines or delete-lines operation, inserting N
   lines or deleting -N lines at vertical position VPOS.  */

static void
x_ins_del_lines (vpos, n)
     int vpos, n;
{
  abort ();
}


/* Scroll part of the display as described by RUN.  */

static void
x_scroll_run (w, run)
     struct window *w;
     struct run *run;
{
  struct frame *f = XFRAME (w->frame);
  int x, y, width, height, from_y, to_y, bottom_y;

  /* Get frame-relative bounding box of the text display area of W,
     without mode lines.  Include in this box the left and right
     fringe of W.  */
  window_box (w, -1, &x, &y, &width, &height);

  from_y = WINDOW_TO_FRAME_PIXEL_Y (w, run->current_y);
  to_y = WINDOW_TO_FRAME_PIXEL_Y (w, run->desired_y);
  bottom_y = y + height;

  if (to_y < from_y)
    {
      /* Scrolling up.  Make sure we don't copy part of the mode
	 line at the bottom.  */
      if (from_y + run->height > bottom_y)
	height = bottom_y - from_y;
      else
	height = run->height;
    }
  else
    {
      /* Scolling down.  Make sure we don't copy over the mode line.
	 at the bottom.  */
      if (to_y + run->height > bottom_y)
	height = bottom_y - to_y;
      else
	height = run->height;
    }

  BLOCK_INPUT;

  /* Cursor off.  Will be switched on again in x_update_window_end.  */
  updated_window = w;
  x_clear_cursor (w);

  mac_scroll_area (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
	         f->output_data.mac->normal_gc,
	         x, from_y,
	         width, height,
	         x, to_y);

  UNBLOCK_INPUT;
}



/***********************************************************************
			   Exposure Events
 ***********************************************************************/


static void
frame_highlight (f)
     struct frame *f;
{
  x_update_cursor (f, 1);
}

static void
frame_unhighlight (f)
     struct frame *f;
{
  x_update_cursor (f, 1);
}

/* The focus has changed.  Update the frames as necessary to reflect
   the new situation.  Note that we can't change the selected frame
   here, because the Lisp code we are interrupting might become confused.
   Each event gets marked with the frame in which it occurred, so the
   Lisp code can tell when the switch took place by examining the events.  */

static void
x_new_focus_frame (dpyinfo, frame)
     struct x_display_info *dpyinfo;
     struct frame *frame;
{
  struct frame *old_focus = dpyinfo->x_focus_frame;

  if (frame != dpyinfo->x_focus_frame)
    {
      /* Set this before calling other routines, so that they see
	 the correct value of x_focus_frame.  */
      dpyinfo->x_focus_frame = frame;

      if (old_focus && old_focus->auto_lower)
	x_lower_frame (old_focus);

#if 0
      selected_frame = frame;
      XSETFRAME (XWINDOW (selected_frame->selected_window)->frame,
		 selected_frame);
      Fselect_window (selected_frame->selected_window, Qnil);
      choose_minibuf_frame ();
#endif /* ! 0 */

      if (dpyinfo->x_focus_frame && dpyinfo->x_focus_frame->auto_raise)
	pending_autoraise_frame = dpyinfo->x_focus_frame;
      else
	pending_autoraise_frame = 0;
    }

  x_frame_rehighlight (dpyinfo);
}

/* Handle an event saying the mouse has moved out of an Emacs frame.  */

void
x_mouse_leave (dpyinfo)
     struct x_display_info *dpyinfo;
{
  x_new_focus_frame (dpyinfo, dpyinfo->x_focus_event_frame);
}

/* The focus has changed, or we have redirected a frame's focus to
   another frame (this happens when a frame uses a surrogate
   mini-buffer frame).  Shift the highlight as appropriate.

   The FRAME argument doesn't necessarily have anything to do with which
   frame is being highlighted or un-highlighted; we only use it to find
   the appropriate X display info.  */

static void
XTframe_rehighlight (frame)
     struct frame *frame;
{
  x_frame_rehighlight (FRAME_X_DISPLAY_INFO (frame));
}

static void
x_frame_rehighlight (dpyinfo)
     struct x_display_info *dpyinfo;
{
  struct frame *old_highlight = dpyinfo->x_highlight_frame;

  if (dpyinfo->x_focus_frame)
    {
      dpyinfo->x_highlight_frame
	= ((GC_FRAMEP (FRAME_FOCUS_FRAME (dpyinfo->x_focus_frame)))
	   ? XFRAME (FRAME_FOCUS_FRAME (dpyinfo->x_focus_frame))
	   : dpyinfo->x_focus_frame);
      if (! FRAME_LIVE_P (dpyinfo->x_highlight_frame))
	{
	  FRAME_FOCUS_FRAME (dpyinfo->x_focus_frame) = Qnil;
	  dpyinfo->x_highlight_frame = dpyinfo->x_focus_frame;
	}
    }
  else
    dpyinfo->x_highlight_frame = 0;

  if (dpyinfo->x_highlight_frame != old_highlight)
    {
      if (old_highlight)
	frame_unhighlight (old_highlight);
      if (dpyinfo->x_highlight_frame)
	frame_highlight (dpyinfo->x_highlight_frame);
    }
}



/* Keyboard processing - modifier keys, vendor-specific keysyms, etc.  */

#if 0 /* MAC_TODO */
/* Initialize mode_switch_bit and modifier_meaning.  */
static void
x_find_modifier_meanings (dpyinfo)
     struct x_display_info *dpyinfo;
{
  int min_code, max_code;
  KeySym *syms;
  int syms_per_code;
  XModifierKeymap *mods;

  dpyinfo->meta_mod_mask = 0;
  dpyinfo->shift_lock_mask = 0;
  dpyinfo->alt_mod_mask = 0;
  dpyinfo->super_mod_mask = 0;
  dpyinfo->hyper_mod_mask = 0;

#ifdef HAVE_X11R4
  XDisplayKeycodes (dpyinfo->display, &min_code, &max_code);
#else
  min_code = dpyinfo->display->min_keycode;
  max_code = dpyinfo->display->max_keycode;
#endif

  syms = XGetKeyboardMapping (dpyinfo->display,
			      min_code, max_code - min_code + 1,
			      &syms_per_code);
  mods = XGetModifierMapping (dpyinfo->display);

  /* Scan the modifier table to see which modifier bits the Meta and
     Alt keysyms are on.  */
  {
    int row, col;	/* The row and column in the modifier table.  */

    for (row = 3; row < 8; row++)
      for (col = 0; col < mods->max_keypermod; col++)
	{
	  KeyCode code
	    = mods->modifiermap[(row * mods->max_keypermod) + col];

	  /* Zeroes are used for filler.  Skip them.  */
	  if (code == 0)
	    continue;

	  /* Are any of this keycode's keysyms a meta key?  */
	  {
	    int code_col;

	    for (code_col = 0; code_col < syms_per_code; code_col++)
	      {
		int sym = syms[((code - min_code) * syms_per_code) + code_col];

		switch (sym)
		  {
		  case XK_Meta_L:
		  case XK_Meta_R:
		    dpyinfo->meta_mod_mask |= (1 << row);
		    break;

		  case XK_Alt_L:
		  case XK_Alt_R:
		    dpyinfo->alt_mod_mask |= (1 << row);
		    break;

		  case XK_Hyper_L:
		  case XK_Hyper_R:
		    dpyinfo->hyper_mod_mask |= (1 << row);
		    break;

		  case XK_Super_L:
		  case XK_Super_R:
		    dpyinfo->super_mod_mask |= (1 << row);
		    break;

		  case XK_Shift_Lock:
		    /* Ignore this if it's not on the lock modifier.  */
		    if ((1 << row) == LockMask)
		      dpyinfo->shift_lock_mask = LockMask;
		    break;
		  }
	      }
	  }
	}
  }

  /* If we couldn't find any meta keys, accept any alt keys as meta keys.  */
  if (! dpyinfo->meta_mod_mask)
    {
      dpyinfo->meta_mod_mask = dpyinfo->alt_mod_mask;
      dpyinfo->alt_mod_mask = 0;
    }

  /* If some keys are both alt and meta,
     make them just meta, not alt.  */
  if (dpyinfo->alt_mod_mask & dpyinfo->meta_mod_mask)
    {
      dpyinfo->alt_mod_mask &= ~dpyinfo->meta_mod_mask;
    }

  XFree ((char *) syms);
  XFreeModifiermap (mods);
}

#endif /* MAC_TODO */

/* Convert between the modifier bits X uses and the modifier bits
   Emacs uses.  */

static unsigned int
x_mac_to_emacs_modifiers (dpyinfo, state)
     struct x_display_info *dpyinfo;
     unsigned short state;
{
  return (((state & shiftKey) ? shift_modifier : 0)
	  | ((state & controlKey) ? ctrl_modifier : 0)
	  | ((state & cmdKey) ? meta_modifier : 0)
	  | ((state & optionKey) ? alt_modifier : 0));
}

#if 0 /* MAC_TODO */
static unsigned short
x_emacs_to_x_modifiers (dpyinfo, state)
     struct x_display_info *dpyinfo;
     unsigned int state;
{
  return (  ((state & alt_modifier)	? dpyinfo->alt_mod_mask   : 0)
	  | ((state & super_modifier)	? dpyinfo->super_mod_mask : 0)
	  | ((state & hyper_modifier)	? dpyinfo->hyper_mod_mask : 0)
	  | ((state & shift_modifier)	? ShiftMask        : 0)
	  | ((state & ctrl_modifier)	? ControlMask      : 0)
	  | ((state & meta_modifier)	? dpyinfo->meta_mod_mask  : 0));
}
#endif /* MAC_TODO */

/* Convert a keysym to its name.  */

char *
x_get_keysym_name (keysym)
     int keysym;
{
  char *value;

  BLOCK_INPUT;
#if 0
  value = XKeysymToString (keysym);
#else
  value = 0;
#endif
  UNBLOCK_INPUT;

  return value;
}



#if 0
/* Mouse clicks and mouse movement.  Rah.  */

/* Prepare a mouse-event in *RESULT for placement in the input queue.

   If the event is a button press, then note that we have grabbed
   the mouse.  */

static Lisp_Object
construct_mouse_click (result, event, f)
     struct input_event *result;
     EventRecord *event;
     struct frame *f;
{
  Point mouseLoc;

  result->kind = MOUSE_CLICK_EVENT;
  result->code = 0;  /* only one mouse button */
  result->timestamp = event->when;
  result->modifiers = event->what == mouseDown ? down_modifier : up_modifier;

  mouseLoc = event->where;

  SetPortWindowPort (FRAME_MAC_WINDOW (f));

  GlobalToLocal (&mouseLoc);
  XSETINT (result->x, mouseLoc.h);
  XSETINT (result->y, mouseLoc.v);

  XSETFRAME (result->frame_or_window, f);

  result->arg = Qnil;
  return Qnil;
}
#endif


/* Function to report a mouse movement to the mainstream Emacs code.
   The input handler calls this.

   We have received a mouse movement event, which is given in *event.
   If the mouse is over a different glyph than it was last time, tell
   the mainstream emacs code by setting mouse_moved.  If not, ask for
   another motion event, so we can check again the next time it moves.  */

static Point last_mouse_motion_position;
static Lisp_Object last_mouse_motion_frame;

static void
note_mouse_movement (frame, pos)
     FRAME_PTR frame;
     Point *pos;
{
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (frame);
#if TARGET_API_MAC_CARBON
  Rect r;
#endif

  last_mouse_movement_time = TickCount () * (1000 / 60);  /* to milliseconds */
  last_mouse_motion_position = *pos;
  XSETFRAME (last_mouse_motion_frame, frame);

#if TARGET_API_MAC_CARBON
  if (!PtInRect (*pos, GetWindowPortBounds (FRAME_MAC_WINDOW (frame), &r)))
#else
  if (!PtInRect (*pos, &FRAME_MAC_WINDOW (frame)->portRect))
#endif
    {
      if (frame == dpyinfo->mouse_face_mouse_frame)
	/* This case corresponds to LeaveNotify in X11.  */
	{
	  /* If we move outside the frame, then we're certainly no
	     longer on any text in the frame.  */
	  clear_mouse_face (dpyinfo);
	  dpyinfo->mouse_face_mouse_frame = 0;
	  if (!dpyinfo->grabbed)
	    rif->define_frame_cursor (frame,
				      frame->output_data.mac->nontext_cursor);
	}
    }
  /* Has the mouse moved off the glyph it was on at the last sighting?  */
  else if (pos->h < last_mouse_glyph.left
	   || pos->h >= last_mouse_glyph.right
	   || pos->v < last_mouse_glyph.top
	   || pos->v >= last_mouse_glyph.bottom)
    {
      frame->mouse_moved = 1;
      last_mouse_scroll_bar = Qnil;
      note_mouse_highlight (frame, pos->h, pos->v);
    }
}

/* This is used for debugging, to turn off note_mouse_highlight.  */

int disable_mouse_highlight;



/************************************************************************
			      Mouse Face
 ************************************************************************/

static struct scroll_bar *x_window_to_scroll_bar ();
static void x_scroll_bar_report_motion ();
static int glyph_rect P_ ((struct frame *f, int, int, Rect *));


/* MAC TODO:  This should be called from somewhere (or removed)  ++KFS */

static void
redo_mouse_highlight ()
{
  if (!NILP (last_mouse_motion_frame)
      && FRAME_LIVE_P (XFRAME (last_mouse_motion_frame)))
    note_mouse_highlight (XFRAME (last_mouse_motion_frame),
			  last_mouse_motion_position.h,
			  last_mouse_motion_position.v);
}


/* Try to determine frame pixel position and size of the glyph under
   frame pixel coordinates X/Y on frame F .  Return the position and
   size in *RECT.  Value is non-zero if we could compute these
   values.  */

static int
glyph_rect (f, x, y, rect)
     struct frame *f;
     int x, y;
     Rect *rect;
{
  Lisp_Object window;

  window = window_from_coordinates (f, x, y, 0, &x, &y, 0);

  if (!NILP (window))
    {
      struct window *w = XWINDOW (window);
      struct glyph_row *r = MATRIX_FIRST_TEXT_ROW (w->current_matrix);
      struct glyph_row *end = r + w->current_matrix->nrows - 1;

      for (; r < end && r->enabled_p; ++r)
	if (r->y <= y && r->y + r->height > y)
	  {
	    /* Found the row at y.  */
	    struct glyph *g = r->glyphs[TEXT_AREA];
	    struct glyph *end = g + r->used[TEXT_AREA];
	    int gx;

	    rect->top = WINDOW_TO_FRAME_PIXEL_Y (w, r->y);
	    rect->bottom = rect->top + r->height;

	    if (x < r->x)
	      {
		/* x is to the left of the first glyph in the row.  */
		/* Shouldn't this be a pixel value?
		   WINDOW_LEFT_EDGE_X (w) seems to be the right value.
		   ++KFS */
		rect->left = WINDOW_LEFT_EDGE_COL (w);
		rect->right = WINDOW_TO_FRAME_PIXEL_X (w, r->x);
		return 1;
	      }

	    for (gx = r->x; g < end; gx += g->pixel_width, ++g)
	      if (gx <= x && gx + g->pixel_width > x)
		{
		  /* x is on a glyph.  */
		  rect->left = WINDOW_TO_FRAME_PIXEL_X (w, gx);
		  rect->right = rect->left + g->pixel_width;
		  return 1;
		}

	    /* x is to the right of the last glyph in the row.  */
	    rect->left = WINDOW_TO_FRAME_PIXEL_X (w, gx);
	    /* Shouldn't this be a pixel value?
	       WINDOW_RIGHT_EDGE_X (w) seems to be the right value.
	       ++KFS */
	    rect->right = WINDOW_RIGHT_EDGE_COL (w);
	    return 1;
	  }
    }

  /* The y is not on any row.  */
  return 0;
}

/* MAC TODO:  This should be called from somewhere (or removed)  ++KFS */

/* Record the position of the mouse in last_mouse_glyph.  */
static void
remember_mouse_glyph (f1, gx, gy)
     struct frame * f1;
     int gx, gy;
{
  if (!glyph_rect (f1, gx, gy, &last_mouse_glyph))
    {
      int width = FRAME_SMALLEST_CHAR_WIDTH (f1);
      int height = FRAME_SMALLEST_FONT_HEIGHT (f1);

      /* Arrange for the division in FRAME_PIXEL_X_TO_COL etc. to
	 round down even for negative values.  */
      if (gx < 0)
	gx -= width - 1;
      if (gy < 0)
	gy -= height - 1;
#if 0
      /* This was the original code from XTmouse_position, but it seems
	 to give the position of the glyph diagonally next to the one
	 the mouse is over.  */
      gx = (gx + width - 1) / width * width;
      gy = (gy + height - 1) / height * height;
#else
      gx = gx / width * width;
      gy = gy / height * height;
#endif

      last_mouse_glyph.left = gx;
      last_mouse_glyph.top = gy;
      last_mouse_glyph.right  = gx + width;
      last_mouse_glyph.bottom = gy + height;
    }
}


static WindowPtr
front_emacs_window ()
{
#if TARGET_API_MAC_CARBON
  WindowPtr wp = GetFrontWindowOfClass (kDocumentWindowClass, true);

  while (wp && !is_emacs_window (wp))
    wp = GetNextWindowOfClass (wp, kDocumentWindowClass, true);
#else
  WindowPtr wp = FrontWindow ();

  while (wp && (wp == tip_window || !is_emacs_window (wp)))
    wp = GetNextWindow (wp);
#endif

  return wp;
}

#define mac_window_to_frame(wp) (((mac_output *) GetWRefCon (wp))->mFP)

/* Return the current position of the mouse.
   *fp should be a frame which indicates which display to ask about.

   If the mouse movement started in a scroll bar, set *fp, *bar_window,
   and *part to the frame, window, and scroll bar part that the mouse
   is over.  Set *x and *y to the portion and whole of the mouse's
   position on the scroll bar.

   If the mouse movement started elsewhere, set *fp to the frame the
   mouse is on, *bar_window to nil, and *x and *y to the character cell
   the mouse is over.

   Set *time to the server time-stamp for the time at which the mouse
   was at this position.

   Don't store anything if we don't have a valid set of values to report.

   This clears the mouse_moved flag, so we can wait for the next mouse
   movement.  */

static void
XTmouse_position (fp, insist, bar_window, part, x, y, time)
     FRAME_PTR *fp;
     int insist;
     Lisp_Object *bar_window;
     enum scroll_bar_part *part;
     Lisp_Object *x, *y;
     unsigned long *time;
{
  Point mouse_pos;
  int ignore1, ignore2;
  WindowPtr wp = front_emacs_window ();
  struct frame *f;
  Lisp_Object frame, tail;

  if (is_emacs_window(wp))
    f = mac_window_to_frame (wp);

  BLOCK_INPUT;

  if (! NILP (last_mouse_scroll_bar) && insist == 0)
    x_scroll_bar_report_motion (fp, bar_window, part, x, y, time);
  else
    {
      /* Clear the mouse-moved flag for every frame on this display.  */
      FOR_EACH_FRAME (tail, frame)
        XFRAME (frame)->mouse_moved = 0;

      last_mouse_scroll_bar = Qnil;

      SetPortWindowPort (wp);

      GetMouse (&mouse_pos);

      pixel_to_glyph_coords (f, mouse_pos.h, mouse_pos.v, &ignore1, &ignore2,
                             &last_mouse_glyph, insist);

      *bar_window = Qnil;
      *part = scroll_bar_handle;
      *fp = f;
      XSETINT (*x, mouse_pos.h);
      XSETINT (*y, mouse_pos.v);
      *time = last_mouse_movement_time;
    }

  UNBLOCK_INPUT;
}


/***********************************************************************
			       Tool-bars
 ***********************************************************************/

/* Handle mouse button event on the tool-bar of frame F, at
   frame-relative coordinates X/Y.  EVENT_TYPE is either ButtionPress
   or ButtonRelase.  */

static void
mac_handle_tool_bar_click (f, button_event)
     struct frame *f;
     EventRecord *button_event;
{
  int x = button_event->where.h;
  int y = button_event->where.v;

  if (button_event->what == mouseDown)
    handle_tool_bar_click (f, x, y, 1, 0);
  else
    handle_tool_bar_click (f, x, y, 0,
			   x_mac_to_emacs_modifiers (FRAME_MAC_DISPLAY_INFO (f),
						     button_event->modifiers));
}


/************************************************************************
			 Scroll bars, general
 ************************************************************************/

/* Create a scroll bar and return the scroll bar vector for it.  W is
   the Emacs window on which to create the scroll bar. TOP, LEFT,
   WIDTH and HEIGHT are the pixel coordinates and dimensions of the
   scroll bar. */

static struct scroll_bar *
x_scroll_bar_create (w, top, left, width, height, disp_top, disp_height)
     struct window *w;
     int top, left, width, height, disp_top, disp_height;
{
  struct frame *f = XFRAME (w->frame);
  struct scroll_bar *bar
    = XSCROLL_BAR (Fmake_vector (make_number (SCROLL_BAR_VEC_SIZE), Qnil));
  Rect r;
  ControlHandle ch;

  BLOCK_INPUT;

  r.left = left;
  r.top = disp_top;
  r.right = left + width;
  r.bottom = disp_top + disp_height;

#if TARGET_API_MAC_CARBON
  ch = NewControl (FRAME_MAC_WINDOW (f), &r, "\p", 1, 0, 0, 0,
		   kControlScrollBarProc, 0L);
#else
  ch = NewControl (FRAME_MAC_WINDOW (f), &r, "\p", 1, 0, 0, 0, scrollBarProc,
		   0L);
#endif
  SET_SCROLL_BAR_CONTROL_HANDLE (bar, ch);
  SetControlReference (ch, (long) bar);

  XSETWINDOW (bar->window, w);
  XSETINT (bar->top, top);
  XSETINT (bar->left, left);
  XSETINT (bar->width, width);
  XSETINT (bar->height, height);
  XSETINT (bar->start, 0);
  XSETINT (bar->end, 0);
  bar->dragging = Qnil;

  /* Add bar to its frame's list of scroll bars.  */
  bar->next = FRAME_SCROLL_BARS (f);
  bar->prev = Qnil;
  XSETVECTOR (FRAME_SCROLL_BARS (f), bar);
  if (!NILP (bar->next))
    XSETVECTOR (XSCROLL_BAR (bar->next)->prev, bar);

  UNBLOCK_INPUT;
  return bar;
}


/* Draw BAR's handle in the proper position.

   If the handle is already drawn from START to END, don't bother
   redrawing it, unless REBUILD is non-zero; in that case, always
   redraw it.  (REBUILD is handy for drawing the handle after expose
   events.)

   Normally, we want to constrain the start and end of the handle to
   fit inside its rectangle, but if the user is dragging the scroll
   bar handle, we want to let them drag it down all the way, so that
   the bar's top is as far down as it goes; otherwise, there's no way
   to move to the very end of the buffer.  */

static void
x_scroll_bar_set_handle (bar, start, end, rebuild)
     struct scroll_bar *bar;
     int start, end;
     int rebuild;
{
  int dragging = ! NILP (bar->dragging);
  ControlHandle ch = SCROLL_BAR_CONTROL_HANDLE (bar);
  FRAME_PTR f = XFRAME (WINDOW_FRAME (XWINDOW (bar->window)));
  int top_range = VERTICAL_SCROLL_BAR_TOP_RANGE (f, XINT (bar->height));
  int length = end - start;

  /* If the display is already accurate, do nothing.  */
  if (! rebuild
      && start == XINT (bar->start)
      && end == XINT (bar->end))
    return;

  BLOCK_INPUT;

  /* Make sure the values are reasonable, and try to preserve the
     distance between start and end.  */
  if (start < 0)
    start = 0;
  else if (start > top_range)
    start = top_range;
  end = start + length;

  if (end < start)
    end = start;
  else if (end > top_range && ! dragging)
    end = top_range;

  /* Store the adjusted setting in the scroll bar.  */
  XSETINT (bar->start, start);
  XSETINT (bar->end, end);

  /* Clip the end position, just for display.  */
  if (end > top_range)
    end = top_range;

  /* Draw bottom positions VERTICAL_SCROLL_BAR_MIN_HANDLE pixels below
     top positions, to make sure the handle is always at least that
     many pixels tall.  */
  end += VERTICAL_SCROLL_BAR_MIN_HANDLE;

  SetControlMinimum (ch, 0);
  /* Don't inadvertently activate deactivated scroll bars */
  if (GetControlMaximum (ch) != -1)
    SetControlMaximum (ch, top_range + VERTICAL_SCROLL_BAR_MIN_HANDLE
		       - (end - start));
  SetControlValue (ch, start);
#if TARGET_API_MAC_CARBON
  SetControlViewSize (ch, end - start);
#endif

  UNBLOCK_INPUT;
}


/* Destroy scroll bar BAR, and set its Emacs window's scroll bar to
   nil.  */

static void
x_scroll_bar_remove (bar)
     struct scroll_bar *bar;
{
  FRAME_PTR f = XFRAME (WINDOW_FRAME (XWINDOW (bar->window)));

  BLOCK_INPUT;

  /* Destroy the Mac scroll bar control  */
  DisposeControl (SCROLL_BAR_CONTROL_HANDLE (bar));

  /* Disassociate this scroll bar from its window.  */
  XWINDOW (bar->window)->vertical_scroll_bar = Qnil;

  UNBLOCK_INPUT;
}

/* Set the handle of the vertical scroll bar for WINDOW to indicate
   that we are displaying PORTION characters out of a total of WHOLE
   characters, starting at POSITION.  If WINDOW has no scroll bar,
   create one.  */
static void
XTset_vertical_scroll_bar (w, portion, whole, position)
     struct window *w;
     int portion, whole, position;
{
  struct frame *f = XFRAME (w->frame);
  struct scroll_bar *bar;
  int top, height, left, sb_left, width, sb_width, disp_top, disp_height;
  int window_y, window_height;

  /* Get window dimensions.  */
  window_box (w, -1, 0, &window_y, 0, &window_height);
  top = window_y;
#ifdef MAC_OSX
  width = 16;
#else
  width = WINDOW_CONFIG_SCROLL_BAR_COLS (w) * FRAME_COLUMN_WIDTH (f);
#endif
  height = window_height;

  /* Compute the left edge of the scroll bar area.  */
  left = WINDOW_SCROLL_BAR_AREA_X (w);

  /* Compute the width of the scroll bar which might be less than
     the width of the area reserved for the scroll bar.  */
  if (WINDOW_CONFIG_SCROLL_BAR_WIDTH (w) > 0)
    sb_width = WINDOW_CONFIG_SCROLL_BAR_WIDTH (w);
  else
    sb_width = width;

  /* Compute the left edge of the scroll bar.  */
  if (WINDOW_HAS_VERTICAL_SCROLL_BAR_ON_RIGHT (w))
    sb_left = left + width - sb_width - (width - sb_width) / 2;
  else
    sb_left = left + (width - sb_width) / 2;

  /* Adjustments according to Inside Macintosh to make it look nice */
  disp_top = top;
  disp_height = height;
  if (disp_top == 0)
    {
      disp_top = -1;
      disp_height++;
    }
  else if (disp_top == FRAME_PIXEL_HEIGHT (f) - 16)
    {
      disp_top++;
      disp_height--;
    }

  if (sb_left + sb_width == FRAME_PIXEL_WIDTH (f))
    sb_left++;

  /* Does the scroll bar exist yet?  */
  if (NILP (w->vertical_scroll_bar))
    {
      BLOCK_INPUT;
      XClearArea (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
		  left, top, width, height, 0);
      UNBLOCK_INPUT;
      bar = x_scroll_bar_create (w, top, sb_left, sb_width, height, disp_top,
				 disp_height);
      XSETVECTOR (w->vertical_scroll_bar, bar);
    }
  else
    {
      /* It may just need to be moved and resized.  */
      ControlHandle ch;

      bar = XSCROLL_BAR (w->vertical_scroll_bar);
      ch = SCROLL_BAR_CONTROL_HANDLE (bar);

      BLOCK_INPUT;

      /* If already correctly positioned, do nothing.  */
      if (XINT (bar->left) == sb_left
          && XINT (bar->top) == top
          && XINT (bar->width) == sb_width
          && XINT (bar->height) == height)
        Draw1Control (ch);
      else
        {
	  /* Clear areas not covered by the scroll bar because it's not as
	     wide as the area reserved for it .  This makes sure a
	     previous mode line display is cleared after C-x 2 C-x 1, for
	     example.  */
	  int area_width = WINDOW_SCROLL_BAR_AREA_WIDTH (w);
	  XClearArea (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
		      left, top, area_width, height, 0);

#if 0
          if (sb_left + sb_width >= FRAME_PIXEL_WIDTH (f))
            XClearArea (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
		        sb_left - 1, top, 1, height, 0);
#endif

          HideControl (ch);
          MoveControl (ch, sb_left + VERTICAL_SCROLL_BAR_WIDTH_TRIM, disp_top);
          SizeControl (ch, sb_width - VERTICAL_SCROLL_BAR_WIDTH_TRIM * 2,
		       disp_height);
          ShowControl (ch);

          /* Remember new settings.  */
          XSETINT (bar->left, sb_left);
          XSETINT (bar->top, top);
          XSETINT (bar->width, sb_width);
          XSETINT (bar->height, height);
        }

      UNBLOCK_INPUT;
    }

  /* Set the scroll bar's current state, unless we're currently being
     dragged.  */
  if (NILP (bar->dragging))
    {
      int top_range = VERTICAL_SCROLL_BAR_TOP_RANGE (f, height);

      if (whole == 0)
	x_scroll_bar_set_handle (bar, 0, top_range, 0);
      else
	{
	  int start = ((double) position * top_range) / whole;
	  int end = ((double) (position + portion) * top_range) / whole;
	  x_scroll_bar_set_handle (bar, start, end, 0);
	}
    }
}


/* The following three hooks are used when we're doing a thorough
   redisplay of the frame.  We don't explicitly know which scroll bars
   are going to be deleted, because keeping track of when windows go
   away is a real pain - "Can you say set-window-configuration, boys
   and girls?"  Instead, we just assert at the beginning of redisplay
   that *all* scroll bars are to be removed, and then save a scroll bar
   from the fiery pit when we actually redisplay its window.  */

/* Arrange for all scroll bars on FRAME to be removed at the next call
   to `*judge_scroll_bars_hook'.  A scroll bar may be spared if
   `*redeem_scroll_bar_hook' is applied to its window before the judgment.  */

static void
XTcondemn_scroll_bars (frame)
     FRAME_PTR frame;
{
  /* Transfer all the scroll bars to FRAME_CONDEMNED_SCROLL_BARS.  */
  while (! NILP (FRAME_SCROLL_BARS (frame)))
    {
      Lisp_Object bar;
      bar = FRAME_SCROLL_BARS (frame);
      FRAME_SCROLL_BARS (frame) = XSCROLL_BAR (bar)->next;
      XSCROLL_BAR (bar)->next = FRAME_CONDEMNED_SCROLL_BARS (frame);
      XSCROLL_BAR (bar)->prev = Qnil;
      if (! NILP (FRAME_CONDEMNED_SCROLL_BARS (frame)))
	XSCROLL_BAR (FRAME_CONDEMNED_SCROLL_BARS (frame))->prev = bar;
      FRAME_CONDEMNED_SCROLL_BARS (frame) = bar;
    }
}


/* Un-mark WINDOW's scroll bar for deletion in this judgment cycle.
   Note that WINDOW isn't necessarily condemned at all.  */

static void
XTredeem_scroll_bar (window)
     struct window *window;
{
  struct scroll_bar *bar;

  /* We can't redeem this window's scroll bar if it doesn't have one.  */
  if (NILP (window->vertical_scroll_bar))
    abort ();

  bar = XSCROLL_BAR (window->vertical_scroll_bar);

  /* Unlink it from the condemned list.  */
  {
    FRAME_PTR f = XFRAME (WINDOW_FRAME (window));

    if (NILP (bar->prev))
      {
	/* If the prev pointer is nil, it must be the first in one of
           the lists.  */
	if (EQ (FRAME_SCROLL_BARS (f), window->vertical_scroll_bar))
	  /* It's not condemned.  Everything's fine.  */
	  return;
	else if (EQ (FRAME_CONDEMNED_SCROLL_BARS (f),
		     window->vertical_scroll_bar))
	  FRAME_CONDEMNED_SCROLL_BARS (f) = bar->next;
	else
	  /* If its prev pointer is nil, it must be at the front of
             one or the other!  */
	  abort ();
      }
    else
      XSCROLL_BAR (bar->prev)->next = bar->next;

    if (! NILP (bar->next))
      XSCROLL_BAR (bar->next)->prev = bar->prev;

    bar->next = FRAME_SCROLL_BARS (f);
    bar->prev = Qnil;
    XSETVECTOR (FRAME_SCROLL_BARS (f), bar);
    if (! NILP (bar->next))
      XSETVECTOR (XSCROLL_BAR (bar->next)->prev, bar);
  }
}

/* Remove all scroll bars on FRAME that haven't been saved since the
   last call to `*condemn_scroll_bars_hook'.  */

static void
XTjudge_scroll_bars (f)
     FRAME_PTR f;
{
  Lisp_Object bar, next;

  bar = FRAME_CONDEMNED_SCROLL_BARS (f);

  /* Clear out the condemned list now so we won't try to process any
     more events on the hapless scroll bars.  */
  FRAME_CONDEMNED_SCROLL_BARS (f) = Qnil;

  for (; ! NILP (bar); bar = next)
    {
      struct scroll_bar *b = XSCROLL_BAR (bar);

      x_scroll_bar_remove (b);

      next = b->next;
      b->next = b->prev = Qnil;
    }

  /* Now there should be no references to the condemned scroll bars,
     and they should get garbage-collected.  */
}


void
activate_scroll_bars (frame)
     FRAME_PTR frame;
{
  Lisp_Object bar;
  ControlHandle ch;

  bar = FRAME_SCROLL_BARS (frame);
  while (! NILP (bar))
    {
      ch = SCROLL_BAR_CONTROL_HANDLE (XSCROLL_BAR (bar));
#if 1 /* TARGET_API_MAC_CARBON */
      ActivateControl (ch);
#else
      SetControlMaximum (ch,
			 VERTICAL_SCROLL_BAR_TOP_RANGE (frame,
							XINT (XSCROLL_BAR (bar)
							      ->height)) - 1);
#endif
      bar = XSCROLL_BAR (bar)->next;
    }
}


void
deactivate_scroll_bars (frame)
     FRAME_PTR frame;
{
  Lisp_Object bar;
  ControlHandle ch;

  bar = FRAME_SCROLL_BARS (frame);
  while (! NILP (bar))
    {
      ch = SCROLL_BAR_CONTROL_HANDLE (XSCROLL_BAR (bar));
#if 1 /* TARGET_API_MAC_CARBON */
      DeactivateControl (ch);
#else
      SetControlMaximum (ch, -1);
#endif
      bar = XSCROLL_BAR (bar)->next;
    }
}

/* Handle a mouse click on the scroll bar BAR.  If *EMACS_EVENT's kind
   is set to something other than NO_EVENT, it is enqueued.

   This may be called from a signal handler, so we have to ignore GC
   mark bits.  */

static void
x_scroll_bar_handle_click (bar, part_code, er, bufp)
     struct scroll_bar *bar;
     int part_code;
     EventRecord *er;
     struct input_event *bufp;
{
  int win_y, top_range;

  if (! GC_WINDOWP (bar->window))
    abort ();

  bufp->kind = SCROLL_BAR_CLICK_EVENT;
  bufp->frame_or_window = bar->window;
  bufp->arg = Qnil;

  bar->dragging = Qnil;

  switch (part_code)
    {
    case kControlUpButtonPart:
      bufp->part = scroll_bar_up_arrow;
      break;
    case kControlDownButtonPart:
      bufp->part = scroll_bar_down_arrow;
      break;
    case kControlPageUpPart:
      bufp->part = scroll_bar_above_handle;
      break;
    case kControlPageDownPart:
      bufp->part = scroll_bar_below_handle;
      break;
#if TARGET_API_MAC_CARBON
    default:
#else
    case kControlIndicatorPart:
#endif
      if (er->what == mouseDown)
        bar->dragging = make_number (0);
      XSETVECTOR (last_mouse_scroll_bar, bar);
      bufp->part = scroll_bar_handle;
      break;
    }

  win_y = XINT (bufp->y) - XINT (bar->top);
  top_range = VERTICAL_SCROLL_BAR_TOP_RANGE (0/*dummy*/, XINT (bar->height));

  win_y -= VERTICAL_SCROLL_BAR_TOP_BORDER;

  win_y -= 24;

  if (! NILP (bar->dragging))
    win_y -= XINT (bar->dragging);

  if (win_y < 0)
    win_y = 0;
  if (win_y > top_range)
    win_y = top_range;

  XSETINT (bufp->x, win_y);
  XSETINT (bufp->y, top_range);
}


/* Handle some mouse motion while someone is dragging the scroll bar.

   This may be called from a signal handler, so we have to ignore GC
   mark bits.  */

static void
x_scroll_bar_note_movement (bar, y_pos, t)
     struct scroll_bar *bar;
     int y_pos;
     Time t;
{
  FRAME_PTR f = XFRAME (XWINDOW (bar->window)->frame);

  last_mouse_movement_time = t;

  f->mouse_moved = 1;
  XSETVECTOR (last_mouse_scroll_bar, bar);

  /* If we're dragging the bar, display it.  */
  if (! GC_NILP (bar->dragging))
    {
      /* Where should the handle be now?  */
      int new_start = y_pos - 24;

      if (new_start != XINT (bar->start))
	{
	  int new_end = new_start + (XINT (bar->end) - XINT (bar->start));

	  x_scroll_bar_set_handle (bar, new_start, new_end, 0);
	}
    }
}


/* Return information to the user about the current position of the
   mouse on the scroll bar.  */

static void
x_scroll_bar_report_motion (fp, bar_window, part, x, y, time)
     FRAME_PTR *fp;
     Lisp_Object *bar_window;
     enum scroll_bar_part *part;
     Lisp_Object *x, *y;
     unsigned long *time;
{
  struct scroll_bar *bar = XSCROLL_BAR (last_mouse_scroll_bar);
  WindowPtr wp = front_emacs_window ();
  Point mouse_pos;
  struct frame *f = mac_window_to_frame (wp);
  int win_y, top_range;

  SetPortWindowPort (wp);

  GetMouse (&mouse_pos);

  win_y = mouse_pos.v - XINT (bar->top);
  top_range = VERTICAL_SCROLL_BAR_TOP_RANGE (f, XINT (bar->height));

  win_y -= VERTICAL_SCROLL_BAR_TOP_BORDER;

  win_y -= 24;

  if (! NILP (bar->dragging))
    win_y -= XINT (bar->dragging);

  if (win_y < 0)
    win_y = 0;
  if (win_y > top_range)
    win_y = top_range;

  *fp = f;
  *bar_window = bar->window;

  if (! NILP (bar->dragging))
    *part = scroll_bar_handle;
  else if (win_y < XINT (bar->start))
    *part = scroll_bar_above_handle;
  else if (win_y < XINT (bar->end) + VERTICAL_SCROLL_BAR_MIN_HANDLE)
    *part = scroll_bar_handle;
  else
    *part = scroll_bar_below_handle;

  XSETINT (*x, win_y);
  XSETINT (*y, top_range);

  f->mouse_moved = 0;
  last_mouse_scroll_bar = Qnil;

  *time = last_mouse_movement_time;
}

/***********************************************************************
			     Text Cursor
 ***********************************************************************/

/* Set clipping for output in glyph row ROW.  W is the window in which
   we operate.  GC is the graphics context to set clipping in.

   ROW may be a text row or, e.g., a mode line.  Text rows must be
   clipped to the interior of the window dedicated to text display,
   mode lines must be clipped to the whole window.  */

static void
x_clip_to_row (w, row, area, gc)
     struct window *w;
     struct glyph_row *row;
     int area;
     GC gc;
{
  struct frame *f = XFRAME (WINDOW_FRAME (w));
  Rect clip_rect;
  int window_x, window_y, window_width;

  window_box (w, area, &window_x, &window_y, &window_width, 0);

  clip_rect.left = window_x;
  clip_rect.top = WINDOW_TO_FRAME_PIXEL_Y (w, row->y);
  clip_rect.top = max (clip_rect.top, window_y);
  clip_rect.right = clip_rect.left + window_width;
  clip_rect.bottom = clip_rect.top + row->visible_height;

  mac_set_clip_rectangle (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f), &clip_rect);
}


/* Draw a hollow box cursor on window W in glyph row ROW.  */

static void
x_draw_hollow_cursor (w, row)
     struct window *w;
     struct glyph_row *row;
{
  struct frame *f = XFRAME (WINDOW_FRAME (w));
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (f);
  Display *dpy = FRAME_MAC_DISPLAY (f);
  int x, y, wd, h;
  XGCValues xgcv;
  struct glyph *cursor_glyph;
  GC gc;

  /* Get the glyph the cursor is on.  If we can't tell because
     the current matrix is invalid or such, give up.  */
  cursor_glyph = get_phys_cursor_glyph (w);
  if (cursor_glyph == NULL)
    return;

  /* Compute frame-relative coordinates for phys cursor.  */
  x = WINDOW_TEXT_TO_FRAME_PIXEL_X (w, w->phys_cursor.x);
  y = get_phys_cursor_geometry (w, row, cursor_glyph, &h);
  wd = w->phys_cursor_width;

  /* The foreground of cursor_gc is typically the same as the normal
     background color, which can cause the cursor box to be invisible.  */
  xgcv.foreground = f->output_data.mac->cursor_pixel;
  if (dpyinfo->scratch_cursor_gc)
    XChangeGC (dpy, dpyinfo->scratch_cursor_gc, GCForeground, &xgcv);
  else
    dpyinfo->scratch_cursor_gc = XCreateGC (dpy, FRAME_MAC_WINDOW (f),
					    GCForeground, &xgcv);
  gc = dpyinfo->scratch_cursor_gc;

  /* Set clipping, draw the rectangle, and reset clipping again.  */
  x_clip_to_row (w, row, TEXT_AREA, gc);
  mac_draw_rectangle (dpy, FRAME_MAC_WINDOW (f), gc, x, y, wd, h);
  mac_reset_clipping (dpy, FRAME_MAC_WINDOW (f));
}


/* Draw a bar cursor on window W in glyph row ROW.

   Implementation note: One would like to draw a bar cursor with an
   angle equal to the one given by the font property XA_ITALIC_ANGLE.
   Unfortunately, I didn't find a font yet that has this property set.
   --gerd.  */

static void
x_draw_bar_cursor (w, row, width, kind)
     struct window *w;
     struct glyph_row *row;
     int width;
     enum text_cursor_kinds kind;
{
  struct frame *f = XFRAME (w->frame);
  struct glyph *cursor_glyph;

  /* If cursor is out of bounds, don't draw garbage.  This can happen
     in mini-buffer windows when switching between echo area glyphs
     and mini-buffer.  */
  cursor_glyph = get_phys_cursor_glyph (w);
  if (cursor_glyph == NULL)
    return;

  /* If on an image, draw like a normal cursor.  That's usually better
     visible than drawing a bar, esp. if the image is large so that
     the bar might not be in the window.  */
  if (cursor_glyph->type == IMAGE_GLYPH)
    {
      struct glyph_row *row;
      row = MATRIX_ROW (w->current_matrix, w->phys_cursor.vpos);
      draw_phys_cursor_glyph (w, row, DRAW_CURSOR);
    }
  else
    {
      Display *dpy = FRAME_MAC_DISPLAY (f);
      Window window = FRAME_MAC_WINDOW (f);
      GC gc = FRAME_MAC_DISPLAY_INFO (f)->scratch_cursor_gc;
      unsigned long mask = GCForeground | GCBackground;
      struct face *face = FACE_FROM_ID (f, cursor_glyph->face_id);
      XGCValues xgcv;

      /* If the glyph's background equals the color we normally draw
	 the bar cursor in, the bar cursor in its normal color is
	 invisible.  Use the glyph's foreground color instead in this
	 case, on the assumption that the glyph's colors are chosen so
	 that the glyph is legible.  */
      if (face->background == f->output_data.mac->cursor_pixel)
	xgcv.background = xgcv.foreground = face->foreground;
      else
	xgcv.background = xgcv.foreground = f->output_data.mac->cursor_pixel;

      if (gc)
	XChangeGC (dpy, gc, mask, &xgcv);
      else
	{
	  gc = XCreateGC (dpy, window, mask, &xgcv);
	  FRAME_MAC_DISPLAY_INFO (f)->scratch_cursor_gc = gc;
	}

      if (width < 0)
	width = FRAME_CURSOR_WIDTH (f);
      width = min (cursor_glyph->pixel_width, width);

      w->phys_cursor_width = width;
      x_clip_to_row (w, row, TEXT_AREA, gc);

      if (kind == BAR_CURSOR)
	XFillRectangle (dpy, window, gc,
			WINDOW_TEXT_TO_FRAME_PIXEL_X (w, w->phys_cursor.x),
			WINDOW_TO_FRAME_PIXEL_Y (w, w->phys_cursor.y),
			width, row->height);
      else
	XFillRectangle (dpy, window, gc,
			WINDOW_TEXT_TO_FRAME_PIXEL_X (w, w->phys_cursor.x),
			WINDOW_TO_FRAME_PIXEL_Y (w, w->phys_cursor.y +
						 row->height - width),
			cursor_glyph->pixel_width,
			width);

      mac_reset_clipping (dpy, FRAME_MAC_WINDOW (f));
    }
}


/* RIF: Define cursor CURSOR on frame F.  */

static void
mac_define_frame_cursor (f, cursor)
     struct frame *f;
     Cursor cursor;
{
#if TARGET_API_MAC_CARBON
  SetThemeCursor (cursor);
#else
  SetCursor (*cursor);
#endif
}


/* RIF: Clear area on frame F.  */

static void
mac_clear_frame_area (f, x, y, width, height)
     struct frame *f;
     int x, y, width, height;
{
  XClearArea (FRAME_MAC_DISPLAY (f), FRAME_MAC_WINDOW (f),
	      x, y, width, height, 0);
}


/* RIF: Draw cursor on window W.  */

static void
mac_draw_window_cursor (w, glyph_row, x, y, cursor_type, cursor_width, on_p, active_p)
     struct window *w;
     struct glyph_row *glyph_row;
     int x, y;
     int cursor_type, cursor_width;
     int on_p, active_p;
{
  if (on_p)
    {
      w->phys_cursor_type = cursor_type;
      w->phys_cursor_on_p = 1;

      if (glyph_row->exact_window_width_line_p
	  && w->phys_cursor.hpos >= glyph_row->used[TEXT_AREA])
	{
	  glyph_row->cursor_in_fringe_p = 1;
	  draw_fringe_bitmap (w, glyph_row, 0);
	}
      else
      switch (cursor_type)
	{
	case HOLLOW_BOX_CURSOR:
	  x_draw_hollow_cursor (w, glyph_row);
	  break;

	case FILLED_BOX_CURSOR:
	  draw_phys_cursor_glyph (w, glyph_row, DRAW_CURSOR);
	  break;

	case BAR_CURSOR:
	  x_draw_bar_cursor (w, glyph_row, cursor_width, BAR_CURSOR);
	  break;

	case HBAR_CURSOR:
	  x_draw_bar_cursor (w, glyph_row, cursor_width, HBAR_CURSOR);
	  break;

	case NO_CURSOR:
	  w->phys_cursor_width = 0;
	  break;

	default:
	  abort ();
	}
    }
}


/* Icons.  */

#if 0 /* MAC_TODO: no icon support yet.  */
int
x_bitmap_icon (f, icon)
     struct frame *f;
     Lisp_Object icon;
{
  HANDLE hicon;

  if (FRAME_W32_WINDOW (f) == 0)
    return 1;

  if (NILP (icon))
    hicon = LoadIcon (hinst, EMACS_CLASS);
  else if (STRINGP (icon))
    hicon = LoadImage (NULL, (LPCTSTR) SDATA (icon), IMAGE_ICON, 0, 0,
		       LR_DEFAULTSIZE | LR_LOADFROMFILE);
  else if (SYMBOLP (icon))
    {
      LPCTSTR name;

      if (EQ (icon, intern ("application")))
	name = (LPCTSTR) IDI_APPLICATION;
      else if (EQ (icon, intern ("hand")))
	name = (LPCTSTR) IDI_HAND;
      else if (EQ (icon, intern ("question")))
	name = (LPCTSTR) IDI_QUESTION;
      else if (EQ (icon, intern ("exclamation")))
	name = (LPCTSTR) IDI_EXCLAMATION;
      else if (EQ (icon, intern ("asterisk")))
	name = (LPCTSTR) IDI_ASTERISK;
      else if (EQ (icon, intern ("winlogo")))
	name = (LPCTSTR) IDI_WINLOGO;
      else
	return 1;

      hicon = LoadIcon (NULL, name);
    }
  else
    return 1;

  if (hicon == NULL)
    return 1;

  PostMessage (FRAME_W32_WINDOW (f), WM_SETICON, (WPARAM) ICON_BIG,
               (LPARAM) hicon);

  return 0;
}
#endif /* MAC_TODO */

/************************************************************************
			  Handling X errors
 ************************************************************************/

/* Display Error Handling functions not used on W32. Listing them here
   helps diff stay in step when comparing w32term.c with xterm.c.

x_error_catcher (display, error)
x_catch_errors (dpy)
x_catch_errors_unwind (old_val)
x_check_errors (dpy, format)
x_had_errors_p (dpy)
x_clear_errors (dpy)
x_uncatch_errors (dpy, count)
x_trace_wire ()
x_connection_signal (signalnum)
x_connection_closed (dpy, error_message)
x_error_quitter (display, error)
x_error_handler (display, error)
x_io_error_quitter (display)

 */


/* Changing the font of the frame.  */

/* Give frame F the font named FONTNAME as its default font, and
   return the full name of that font.  FONTNAME may be a wildcard
   pattern; in that case, we choose some font that fits the pattern.
   The return value shows which font we chose.  */

Lisp_Object
x_new_font (f, fontname)
     struct frame *f;
     register char *fontname;
{
  struct font_info *fontp
    = FS_LOAD_FONT (f, 0, fontname, -1);

  if (!fontp)
    return Qnil;

  FRAME_FONT (f) = (XFontStruct *) (fontp->font);
  FRAME_BASELINE_OFFSET (f) = fontp->baseline_offset;
  FRAME_FONTSET (f) = -1;

  FRAME_COLUMN_WIDTH (f) = fontp->average_width;
  FRAME_SPACE_WIDTH (f) = fontp->space_width;
  FRAME_LINE_HEIGHT (f) = FONT_HEIGHT (FRAME_FONT (f));

  compute_fringe_widths (f, 1);

  /* Compute the scroll bar width in character columns.  */
  if (FRAME_CONFIG_SCROLL_BAR_WIDTH (f) > 0)
    {
      int wid = FRAME_COLUMN_WIDTH (f);
      FRAME_CONFIG_SCROLL_BAR_COLS (f)
	= (FRAME_CONFIG_SCROLL_BAR_WIDTH (f) + wid-1) / wid;
    }
  else
    {
      int wid = FRAME_COLUMN_WIDTH (f);
      FRAME_CONFIG_SCROLL_BAR_COLS (f) = (14 + wid - 1) / wid;
    }

  /* Now make the frame display the given font.  */
  if (FRAME_MAC_WINDOW (f) != 0)
    {
      XSetFont (FRAME_MAC_DISPLAY (f), f->output_data.mac->normal_gc,
		FRAME_FONT (f));
      XSetFont (FRAME_MAC_DISPLAY (f), f->output_data.mac->reverse_gc,
		FRAME_FONT (f));
      XSetFont (FRAME_MAC_DISPLAY (f), f->output_data.mac->cursor_gc,
		FRAME_FONT (f));

      /* Don't change the size of a tip frame; there's no point in
	 doing it because it's done in Fx_show_tip, and it leads to
	 problems because the tip frame has no widget.  */
      if (NILP (tip_frame) || XFRAME (tip_frame) != f)
        x_set_window_size (f, 0, FRAME_COLS (f), FRAME_LINES (f));
    }

  return build_string (fontp->full_name);
}

/* Give frame F the fontset named FONTSETNAME as its default font, and
   return the full name of that fontset.  FONTSETNAME may be a wildcard
   pattern; in that case, we choose some fontset that fits the pattern.
   The return value shows which fontset we chose.  */

Lisp_Object
x_new_fontset (f, fontsetname)
     struct frame *f;
     char *fontsetname;
{
  int fontset = fs_query_fontset (build_string (fontsetname), 0);
  Lisp_Object result;

  if (fontset < 0)
    return Qnil;

  if (FRAME_FONTSET (f) == fontset)
    /* This fontset is already set in frame F.  There's nothing more
       to do.  */
    return fontset_name (fontset);

  result = x_new_font (f, (SDATA (fontset_ascii (fontset))));

  if (!STRINGP (result))
    /* Can't load ASCII font.  */
    return Qnil;

  /* Since x_new_font doesn't update any fontset information, do it now.  */
  FRAME_FONTSET(f) = fontset;

  return build_string (fontsetname);
}


/***********************************************************************
	TODO: W32 Input Methods
 ***********************************************************************/
/* Listing missing functions from xterm.c helps diff stay in step.

xim_destroy_callback (xim, client_data, call_data)
xim_open_dpy (dpyinfo, resource_name)
struct xim_inst_t
xim_instantiate_callback (display, client_data, call_data)
xim_initialize (dpyinfo, resource_name)
xim_close_dpy (dpyinfo)

 */


void
mac_get_window_bounds (f, inner, outer)
     struct frame *f;
     Rect *inner, *outer;
{
#if TARGET_API_MAC_CARBON
  GetWindowBounds (FRAME_MAC_WINDOW (f), kWindowContentRgn, inner);
  GetWindowBounds (FRAME_MAC_WINDOW (f), kWindowStructureRgn, outer);
#else /* not TARGET_API_MAC_CARBON */
  RgnHandle region = NewRgn ();

  GetWindowRegion (FRAME_MAC_WINDOW (f), kWindowContentRgn, region);
  *inner = (*region)->rgnBBox;
  GetWindowRegion (FRAME_MAC_WINDOW (f), kWindowStructureRgn, region);
  *outer = (*region)->rgnBBox;
  DisposeRgn (region);
#endif /* not TARGET_API_MAC_CARBON */
}


/* Calculate the absolute position in frame F
   from its current recorded position values and gravity.  */

void
x_calc_absolute_position (f)
     struct frame *f;
{
  int width_diff = 0, height_diff = 0;
  int flags = f->size_hint_flags;
  Rect inner, outer;

  /* We have nothing to do if the current position
     is already for the top-left corner.  */
  if (! ((flags & XNegative) || (flags & YNegative)))
    return;

  /* Find the offsets of the outside upper-left corner of
     the inner window, with respect to the outer window.  */
  mac_get_window_bounds (f, &inner, &outer);

  width_diff = (outer.right - outer.left) - (inner.right - inner.left);
  height_diff = (outer.bottom - outer.top) - (inner.bottom - inner.top);

  /* Treat negative positions as relative to the leftmost bottommost
     position that fits on the screen.  */
  if (flags & XNegative)
    f->left_pos = (FRAME_MAC_DISPLAY_INFO (f)->width
                   - width_diff
		   - FRAME_PIXEL_WIDTH (f)
		   + f->left_pos);

  if (flags & YNegative)
    f->top_pos = (FRAME_MAC_DISPLAY_INFO (f)->height
		  - height_diff
		  - FRAME_PIXEL_HEIGHT (f)
		  + f->top_pos);

  /* The left_pos and top_pos
     are now relative to the top and left screen edges,
     so the flags should correspond.  */
  f->size_hint_flags &= ~ (XNegative | YNegative);
}

/* CHANGE_GRAVITY is 1 when calling from Fset_frame_position,
   to really change the position, and 0 when calling from
   x_make_frame_visible (in that case, XOFF and YOFF are the current
   position values).  It is -1 when calling from x_set_frame_parameters,
   which means, do adjust for borders but don't change the gravity.  */

void
x_set_offset (f, xoff, yoff, change_gravity)
     struct frame *f;
     register int xoff, yoff;
     int change_gravity;
{
  if (change_gravity > 0)
    {
      f->top_pos = yoff;
      f->left_pos = xoff;
      f->size_hint_flags &= ~ (XNegative | YNegative);
      if (xoff < 0)
	f->size_hint_flags |= XNegative;
      if (yoff < 0)
	f->size_hint_flags |= YNegative;
      f->win_gravity = NorthWestGravity;
    }
  x_calc_absolute_position (f);

  BLOCK_INPUT;
  x_wm_set_size_hint (f, (long) 0, 0);

#if TARGET_API_MAC_CARBON
  MoveWindowStructure (FRAME_MAC_WINDOW (f), f->left_pos, f->top_pos);
  /* If the title bar is completely outside the screen, adjust the
     position. */
  ConstrainWindowToScreen (FRAME_MAC_WINDOW (f), kWindowTitleBarRgn,
			   kWindowConstrainMoveRegardlessOfFit
			   | kWindowConstrainAllowPartial, NULL, NULL);
  x_real_positions (f, &f->left_pos, &f->top_pos);
#else
  {
    Rect inner, outer, screen_rect, dummy;
    RgnHandle region = NewRgn ();

    mac_get_window_bounds (f, &inner, &outer);
    f->x_pixels_diff = inner.left - outer.left;
    f->y_pixels_diff = inner.top - outer.top;
    MoveWindow (FRAME_MAC_WINDOW (f), f->left_pos + f->x_pixels_diff,
		f->top_pos + f->y_pixels_diff, false);

    /* If the title bar is completely outside the screen, adjust the
       position.  The variable `outer' holds the title bar rectangle.
       The variable `inner' holds slightly smaller one than `outer',
       so that the calculation of overlapping may not become too
       strict.  */
    GetWindowRegion (FRAME_MAC_WINDOW (f), kWindowTitleBarRgn, region);
    outer = (*region)->rgnBBox;
    DisposeRgn (region);
    inner = outer;
    InsetRect (&inner, 8, 8);
    screen_rect = qd.screenBits.bounds;
    screen_rect.top += GetMBarHeight ();

    if (!SectRect (&inner, &screen_rect, &dummy))
      {
	if (inner.right <= screen_rect.left)
	  f->left_pos = screen_rect.left;
	else if (inner.left >= screen_rect.right)
	  f->left_pos = screen_rect.right - (outer.right - outer.left);

	if (inner.bottom <= screen_rect.top)
	  f->top_pos = screen_rect.top;
	else if (inner.top >= screen_rect.bottom)
	  f->top_pos = screen_rect.bottom - (outer.bottom - outer.top);

	MoveWindow (FRAME_MAC_WINDOW (f), f->left_pos + f->x_pixels_diff,
		    f->top_pos + f->y_pixels_diff, false);
      }
  }
#endif

  UNBLOCK_INPUT;
}

/* Call this to change the size of frame F's x-window.
   If CHANGE_GRAVITY is 1, we change to top-left-corner window gravity
   for this size change and subsequent size changes.
   Otherwise we leave the window gravity unchanged.  */

void
x_set_window_size (f, change_gravity, cols, rows)
     struct frame *f;
     int change_gravity;
     int cols, rows;
{
  int pixelwidth, pixelheight;

  BLOCK_INPUT;

  check_frame_size (f, &rows, &cols);
  f->scroll_bar_actual_width
    = FRAME_SCROLL_BAR_COLS (f) * FRAME_COLUMN_WIDTH (f);

  compute_fringe_widths (f, 0);

  pixelwidth = FRAME_TEXT_COLS_TO_PIXEL_WIDTH (f, cols);
  pixelheight = FRAME_TEXT_LINES_TO_PIXEL_HEIGHT (f, rows);

  f->win_gravity = NorthWestGravity;
  x_wm_set_size_hint (f, (long) 0, 0);

  SizeWindow (FRAME_MAC_WINDOW (f), pixelwidth, pixelheight, 0);

  /* Now, strictly speaking, we can't be sure that this is accurate,
     but the window manager will get around to dealing with the size
     change request eventually, and we'll hear how it went when the
     ConfigureNotify event gets here.

     We could just not bother storing any of this information here,
     and let the ConfigureNotify event set everything up, but that
     might be kind of confusing to the Lisp code, since size changes
     wouldn't be reported in the frame parameters until some random
     point in the future when the ConfigureNotify event arrives.

     We pass 1 for DELAY since we can't run Lisp code inside of
     a BLOCK_INPUT.  */
  change_frame_size (f, rows, cols, 0, 1, 0);
  FRAME_PIXEL_WIDTH (f) = pixelwidth;
  FRAME_PIXEL_HEIGHT (f) = pixelheight;

  /* We've set {FRAME,PIXEL}_{WIDTH,HEIGHT} to the values we hope to
     receive in the ConfigureNotify event; if we get what we asked
     for, then the event won't cause the screen to become garbaged, so
     we have to make sure to do it here.  */
  SET_FRAME_GARBAGED (f);

  XFlush (FRAME_X_DISPLAY (f));

  /* If cursor was outside the new size, mark it as off.  */
  mark_window_cursors_off (XWINDOW (f->root_window));

  /* Clear out any recollection of where the mouse highlighting was,
     since it might be in a place that's outside the new frame size.
     Actually checking whether it is outside is a pain in the neck,
     so don't try--just let the highlighting be done afresh with new size.  */
  cancel_mouse_face (f);

  UNBLOCK_INPUT;
}

/* Mouse warping.  */

void x_set_mouse_pixel_position (struct frame *f, int pix_x, int pix_y);

void
x_set_mouse_position (f, x, y)
     struct frame *f;
     int x, y;
{
  int pix_x, pix_y;

  pix_x = FRAME_COL_TO_PIXEL_X (f, x) + FRAME_COLUMN_WIDTH (f) / 2;
  pix_y = FRAME_LINE_TO_PIXEL_Y (f, y) + FRAME_LINE_HEIGHT (f) / 2;

  if (pix_x < 0) pix_x = 0;
  if (pix_x > FRAME_PIXEL_WIDTH (f)) pix_x = FRAME_PIXEL_WIDTH (f);

  if (pix_y < 0) pix_y = 0;
  if (pix_y > FRAME_PIXEL_HEIGHT (f)) pix_y = FRAME_PIXEL_HEIGHT (f);

  x_set_mouse_pixel_position (f, pix_x, pix_y);
}

void
x_set_mouse_pixel_position (f, pix_x, pix_y)
     struct frame *f;
     int pix_x, pix_y;
{
#if 0 /* MAC_TODO: CursorDeviceMoveTo is non-Carbon */
  BLOCK_INPUT;

  XWarpPointer (FRAME_X_DISPLAY (f), None, FRAME_X_WINDOW (f),
		0, 0, 0, 0, pix_x, pix_y);
  UNBLOCK_INPUT;
#endif
}


/* focus shifting, raising and lowering.  */

void
x_focus_on_frame (f)
     struct frame *f;
{
#if 0  /* This proves to be unpleasant.  */
  x_raise_frame (f);
#endif
#if 0
  /* I don't think that the ICCCM allows programs to do things like this
     without the interaction of the window manager.  Whatever you end up
     doing with this code, do it to x_unfocus_frame too.  */
  XSetInputFocus (FRAME_X_DISPLAY (f), FRAME_X_WINDOW (f),
		  RevertToPointerRoot, CurrentTime);
#endif /* ! 0 */
}

void
x_unfocus_frame (f)
     struct frame *f;
{
}

/* Raise frame F.  */
void
x_raise_frame (f)
     struct frame *f;
{
  if (f->async_visible)
    {
      BLOCK_INPUT;
      SelectWindow (FRAME_MAC_WINDOW (f));
      UNBLOCK_INPUT;
    }
}

/* Lower frame F.  */
void
x_lower_frame (f)
     struct frame *f;
{
  if (f->async_visible)
    {
      BLOCK_INPUT;
      SendBehind (FRAME_MAC_WINDOW (f), nil);
      UNBLOCK_INPUT;
    }
}

static void
XTframe_raise_lower (f, raise_flag)
     FRAME_PTR f;
     int raise_flag;
{
  if (raise_flag)
    x_raise_frame (f);
  else
    x_lower_frame (f);
}

/* Change of visibility.  */

/* This tries to wait until the frame is really visible.
   However, if the window manager asks the user where to position
   the frame, this will return before the user finishes doing that.
   The frame will not actually be visible at that time,
   but it will become visible later when the window manager
   finishes with it.  */

void
x_make_frame_visible (f)
     struct frame *f;
{
  Lisp_Object type;
  int original_top, original_left;

  BLOCK_INPUT;

  if (! FRAME_VISIBLE_P (f))
    {
      /* We test FRAME_GARBAGED_P here to make sure we don't
	 call x_set_offset a second time
	 if we get to x_make_frame_visible a second time
	 before the window gets really visible.  */
      if (! FRAME_ICONIFIED_P (f)
	  && ! f->output_data.mac->asked_for_visible)
	x_set_offset (f, f->left_pos, f->top_pos, 0);

      f->output_data.mac->asked_for_visible = 1;

#if TARGET_API_MAC_CARBON
      if (!(FRAME_SIZE_HINTS (f)->flags & (USPosition | PPosition)))
	{
	  struct frame *sf = SELECTED_FRAME ();
	  if (!FRAME_MAC_P (sf))
	    RepositionWindow (FRAME_MAC_WINDOW (f), NULL,
			      kWindowCenterOnMainScreen);
	  else
	    RepositionWindow (FRAME_MAC_WINDOW (f),
			      FRAME_MAC_WINDOW (sf),
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1020
			      kWindowCascadeStartAtParentWindowScreen
#else
			      kWindowCascadeOnParentWindowScreen
#endif
			      );
	  x_real_positions (f, &f->left_pos, &f->top_pos);
	}
#endif
      ShowWindow (FRAME_MAC_WINDOW (f));
    }

  XFlush (FRAME_MAC_DISPLAY (f));

  /* Synchronize to ensure Emacs knows the frame is visible
     before we do anything else.  We do this loop with input not blocked
     so that incoming events are handled.  */
  {
    Lisp_Object frame;
    int count;

    /* This must come after we set COUNT.  */
    UNBLOCK_INPUT;

    XSETFRAME (frame, f);

    /* Wait until the frame is visible.  Process X events until a
       MapNotify event has been seen, or until we think we won't get a
       MapNotify at all..  */
    for (count = input_signal_count + 10;
	 input_signal_count < count && !FRAME_VISIBLE_P (f);)
      {
	/* Force processing of queued events.  */
	x_sync (f);

	/* Machines that do polling rather than SIGIO have been
	   observed to go into a busy-wait here.  So we'll fake an
	   alarm signal to let the handler know that there's something
	   to be read.  We used to raise a real alarm, but it seems
	   that the handler isn't always enabled here.  This is
	   probably a bug.  */
	if (input_polling_used ())
	  {
	    /* It could be confusing if a real alarm arrives while
	       processing the fake one.  Turn it off and let the
	       handler reset it.  */
	    extern void poll_for_input_1 P_ ((void));
	    int old_poll_suppress_count = poll_suppress_count;
	    poll_suppress_count = 1;
	    poll_for_input_1 ();
	    poll_suppress_count = old_poll_suppress_count;
	  }

	/* See if a MapNotify event has been processed.  */
	FRAME_SAMPLE_VISIBILITY (f);
      }
  }
}

/* Change from mapped state to withdrawn state.  */

/* Make the frame visible (mapped and not iconified).  */

void
x_make_frame_invisible (f)
     struct frame *f;
{
  /* Don't keep the highlight on an invisible frame.  */
  if (FRAME_MAC_DISPLAY_INFO (f)->x_highlight_frame == f)
    FRAME_MAC_DISPLAY_INFO (f)->x_highlight_frame = 0;

  BLOCK_INPUT;

  HideWindow (FRAME_MAC_WINDOW (f));

  /* We can't distinguish this from iconification
     just by the event that we get from the server.
     So we can't win using the usual strategy of letting
     FRAME_SAMPLE_VISIBILITY set this.  So do it by hand,
     and synchronize with the server to make sure we agree.  */
  f->visible = 0;
  FRAME_ICONIFIED_P (f) = 0;
  f->async_visible = 0;
  f->async_iconified = 0;

  UNBLOCK_INPUT;
}

/* Change window state from mapped to iconified.  */

void
x_iconify_frame (f)
     struct frame *f;
{
  /* Don't keep the highlight on an invisible frame.  */
  if (FRAME_MAC_DISPLAY_INFO (f)->x_highlight_frame == f)
    FRAME_MAC_DISPLAY_INFO (f)->x_highlight_frame = 0;

#if 0
  /* Review:  Since window is still visible in dock, still allow updates? */
  if (f->async_iconified)
    return;
#endif

  BLOCK_INPUT;

  CollapseWindow (FRAME_MAC_WINDOW (f), true);

  UNBLOCK_INPUT;
}


/* Free X resources of frame F.  */

void
x_free_frame_resources (f)
     struct frame *f;
{
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (f);
  WindowPtr wp = FRAME_MAC_WINDOW (f);

  BLOCK_INPUT;

  if (wp != tip_window)
    remove_window_handler (wp);

  DisposeWindow (wp);
  if (wp == tip_window)
    /* Neither WaitNextEvent nor ReceiveNextEvent receives `window
       closed' event.  So we reset tip_window here.  */
    tip_window = NULL;

  free_frame_menubar (f);

  if (FRAME_FACE_CACHE (f))
    free_frame_faces (f);

  x_free_gcs (f);

  if (FRAME_SIZE_HINTS (f))
    xfree (FRAME_SIZE_HINTS (f));

  xfree (f->output_data.mac);
  f->output_data.mac = NULL;

  if (f == dpyinfo->x_focus_frame)
    dpyinfo->x_focus_frame = 0;
  if (f == dpyinfo->x_focus_event_frame)
    dpyinfo->x_focus_event_frame = 0;
  if (f == dpyinfo->x_highlight_frame)
    dpyinfo->x_highlight_frame = 0;

  if (f == dpyinfo->mouse_face_mouse_frame)
    {
      dpyinfo->mouse_face_beg_row
	= dpyinfo->mouse_face_beg_col = -1;
      dpyinfo->mouse_face_end_row
	= dpyinfo->mouse_face_end_col = -1;
      dpyinfo->mouse_face_window = Qnil;
      dpyinfo->mouse_face_deferred_gc = 0;
      dpyinfo->mouse_face_mouse_frame = 0;
    }

  UNBLOCK_INPUT;
}


/* Destroy the X window of frame F.  */

void
x_destroy_window (f)
     struct frame *f;
{
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (f);

  x_free_frame_resources (f);

  dpyinfo->reference_count--;
}


/* Setting window manager hints.  */

/* Set the normal size hints for the window manager, for frame F.
   FLAGS is the flags word to use--or 0 meaning preserve the flags
   that the window now has.
   If USER_POSITION is nonzero, we set the USPosition
   flag (this is useful when FLAGS is 0).  */
void
x_wm_set_size_hint (f, flags, user_position)
     struct frame *f;
     long flags;
     int user_position;
{
  int base_width, base_height, width_inc, height_inc;
  int min_rows = 0, min_cols = 0;
  XSizeHints *size_hints;

  base_width = FRAME_TEXT_COLS_TO_PIXEL_WIDTH (f, 0);
  base_height = FRAME_TEXT_LINES_TO_PIXEL_HEIGHT (f, 0);
  width_inc = FRAME_COLUMN_WIDTH (f);
  height_inc = FRAME_LINE_HEIGHT (f);

  check_frame_size (f, &min_rows, &min_cols);

  size_hints = FRAME_SIZE_HINTS (f);
  if (size_hints == NULL)
    {
      size_hints = FRAME_SIZE_HINTS (f) = xmalloc (sizeof (XSizeHints));
      bzero (size_hints, sizeof (XSizeHints));
    }

  size_hints->flags |= PResizeInc | PMinSize | PBaseSize ;
  size_hints->width_inc  = width_inc;
  size_hints->height_inc = height_inc;
  size_hints->min_width  = base_width + min_cols * width_inc;
  size_hints->min_height = base_height + min_rows * height_inc;
  size_hints->base_width  = base_width;
  size_hints->base_height = base_height;

  if (flags)
    size_hints->flags = flags;
  else if (user_position)
    {
      size_hints->flags &= ~ PPosition;
      size_hints->flags |= USPosition;
    }
}

#if 0 /* MAC_TODO: hide application instead of iconify? */
/* Used for IconicState or NormalState */

void
x_wm_set_window_state (f, state)
     struct frame *f;
     int state;
{
#ifdef USE_X_TOOLKIT
  Arg al[1];

  XtSetArg (al[0], XtNinitialState, state);
  XtSetValues (f->output_data.x->widget, al, 1);
#else /* not USE_X_TOOLKIT */
  Window window = FRAME_X_WINDOW (f);

  f->output_data.x->wm_hints.flags |= StateHint;
  f->output_data.x->wm_hints.initial_state = state;

  XSetWMHints (FRAME_X_DISPLAY (f), window, &f->output_data.x->wm_hints);
#endif /* not USE_X_TOOLKIT */
}

void
x_wm_set_icon_pixmap (f, pixmap_id)
     struct frame *f;
     int pixmap_id;
{
  Pixmap icon_pixmap;

#ifndef USE_X_TOOLKIT
  Window window = FRAME_X_WINDOW (f);
#endif

  if (pixmap_id > 0)
    {
      icon_pixmap = x_bitmap_pixmap (f, pixmap_id);
      f->output_data.x->wm_hints.icon_pixmap = icon_pixmap;
    }
  else
    {
      /* It seems there is no way to turn off use of an icon pixmap.
	 The following line does it, only if no icon has yet been created,
	 for some window managers.  But with mwm it crashes.
	 Some people say it should clear the IconPixmapHint bit in this case,
	 but that doesn't work, and the X consortium said it isn't the
	 right thing at all.  Since there is no way to win,
	 best to explicitly give up.  */
#if 0
      f->output_data.x->wm_hints.icon_pixmap = None;
#else
      return;
#endif
    }

#ifdef USE_X_TOOLKIT /* same as in x_wm_set_window_state.  */

  {
    Arg al[1];
    XtSetArg (al[0], XtNiconPixmap, icon_pixmap);
    XtSetValues (f->output_data.x->widget, al, 1);
  }

#else /* not USE_X_TOOLKIT */

  f->output_data.x->wm_hints.flags |= IconPixmapHint;
  XSetWMHints (FRAME_X_DISPLAY (f), window, &f->output_data.x->wm_hints);

#endif /* not USE_X_TOOLKIT */
}

#endif /* MAC_TODO */

void
x_wm_set_icon_position (f, icon_x, icon_y)
     struct frame *f;
     int icon_x, icon_y;
{
#if 0 /* MAC_TODO: no icons on Mac */
#ifdef USE_X_TOOLKIT
  Window window = XtWindow (f->output_data.x->widget);
#else
  Window window = FRAME_X_WINDOW (f);
#endif

  f->output_data.x->wm_hints.flags |= IconPositionHint;
  f->output_data.x->wm_hints.icon_x = icon_x;
  f->output_data.x->wm_hints.icon_y = icon_y;

  XSetWMHints (FRAME_X_DISPLAY (f), window, &f->output_data.x->wm_hints);
#endif /* MAC_TODO */
}


/***********************************************************************
				Fonts
 ***********************************************************************/

/* Return a pointer to struct font_info of font FONT_IDX of frame F.  */

struct font_info *
x_get_font_info (f, font_idx)
     FRAME_PTR f;
     int font_idx;
{
  return (FRAME_MAC_FONT_TABLE (f) + font_idx);
}

/* the global font name table */
char **font_name_table = NULL;
int font_name_table_size = 0;
int font_name_count = 0;

#if 0
/* compare two strings ignoring case */
static int
stricmp (const char *s, const char *t)
{
  for ( ; tolower (*s) == tolower (*t); s++, t++)
    if (*s == '\0')
      return 0;
  return tolower (*s) - tolower (*t);
}

/* compare two strings ignoring case and handling wildcard */
static int
wildstrieq (char *s1, char *s2)
{
  if (strcmp (s1, "*") == 0 || strcmp (s2, "*") == 0)
    return true;

  return stricmp (s1, s2) == 0;
}

/* Assume parameter 1 is fully qualified, no wildcards. */
static int
mac_font_pattern_match (fontname, pattern)
    char * fontname;
    char * pattern;
{
  char *regex = (char *) alloca (strlen (pattern) * 2 + 3);
  char *font_name_copy = (char *) alloca (strlen (fontname) + 1);
  char *ptr;

  /* Copy fontname so we can modify it during comparison.  */
  strcpy (font_name_copy, fontname);

  ptr = regex;
  *ptr++ = '^';

  /* Turn pattern into a regexp and do a regexp match.  */
  for (; *pattern; pattern++)
    {
      if (*pattern == '?')
        *ptr++ = '.';
      else if (*pattern == '*')
        {
          *ptr++ = '.';
          *ptr++ = '*';
        }
      else
        *ptr++ = *pattern;
    }
  *ptr = '$';
  *(ptr + 1) = '\0';

  return (fast_c_string_match_ignore_case (build_string (regex),
                                           font_name_copy) >= 0);
}

/* Two font specs are considered to match if their foundry, family,
   weight, slant, and charset match.  */
static int
mac_font_match (char *mf, char *xf)
{
  char m_foundry[50], m_family[50], m_weight[20], m_slant[2], m_charset[20];
  char x_foundry[50], x_family[50], x_weight[20], x_slant[2], x_charset[20];

  if (sscanf (mf, "-%49[^-]-%49[^-]-%19[^-]-%1[^-]-%*[^-]--%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]-%19s",
              m_foundry, m_family, m_weight, m_slant, m_charset) != 5)
    return mac_font_pattern_match (mf, xf);

  if (sscanf (xf, "-%49[^-]-%49[^-]-%19[^-]-%1[^-]-%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]-%19s",
              x_foundry, x_family, x_weight, x_slant, x_charset) != 5)
    return mac_font_pattern_match (mf, xf);

  return (wildstrieq (m_foundry, x_foundry)
          && wildstrieq (m_family, x_family)
          && wildstrieq (m_weight, x_weight)
          && wildstrieq (m_slant, x_slant)
          && wildstrieq (m_charset, x_charset))
         || mac_font_pattern_match (mf, xf);
}
#endif

static Lisp_Object Qbig5, Qcn_gb, Qsjis, Qeuc_kr;

static void
decode_mac_font_name (name, size, scriptcode)
     char *name;
     int size;
#if TARGET_API_MAC_CARBON
     int scriptcode;
#else
     short scriptcode;
#endif
{
  Lisp_Object coding_system;
  struct coding_system coding;
  char *buf;

  switch (scriptcode)
    {
    case smTradChinese:
      coding_system = Qbig5;
      break;
    case smSimpChinese:
      coding_system = Qcn_gb;
      break;
    case smJapanese:
      coding_system = Qsjis;
      break;
    case smKorean:
      coding_system = Qeuc_kr;
      break;
    default:
      return;
    }

  setup_coding_system (coding_system, &coding);
  coding.src_multibyte = 0;
  coding.dst_multibyte = 1;
  coding.mode |= CODING_MODE_LAST_BLOCK;
  coding.composing = COMPOSITION_DISABLED;
  buf = (char *) alloca (size);

  decode_coding (&coding, name, buf, strlen (name), size - 1);
  bcopy (buf, name, coding.produced);
  name[coding.produced] = '\0';
}


static char *
mac_to_x_fontname (name, size, style, scriptcode)
     char *name;
     int size;
     Style style;
#if TARGET_API_MAC_CARBON
     int scriptcode;
#else
     short scriptcode;
#endif
{
  char foundry[32], family[32], cs[32];
  char xf[256], *result, *p;

  if (sscanf (name, "%31[^-]-%31[^-]-%31s", foundry, family, cs) != 3)
    {
      strcpy(foundry, "Apple");
      strcpy(family, name);

      switch (scriptcode)
      {
      case smTradChinese:	/* == kTextEncodingMacChineseTrad */
        strcpy(cs, "big5-0");
        break;
      case smSimpChinese:	/* == kTextEncodingMacChineseSimp */
        strcpy(cs, "gb2312.1980-0");
        break;
      case smJapanese:		/* == kTextEncodingMacJapanese */
        strcpy(cs, "jisx0208.1983-sjis");
        break;
      case -smJapanese:
	/* Each Apple Japanese font is entered into the font table
	   twice: once as a jisx0208.1983-sjis font and once as a
	   jisx0201.1976-0 font.  The latter can be used to display
	   the ascii charset and katakana-jisx0201 charset.  A
	   negative script code signals that the name of this latter
	   font is being built.  */
	strcpy(cs, "jisx0201.1976-0");
	break;
      case smKorean:		/* == kTextEncodingMacKorean */
        strcpy(cs, "ksc5601.1989-0");
        break;
#if TARGET_API_MAC_CARBON
      case kTextEncodingMacCyrillic:
	strcpy(cs, "mac-cyrillic");
	break;
      case kTextEncodingMacCentralEurRoman:
	strcpy(cs, "mac-centraleurroman");
	break;
      case kTextEncodingMacSymbol:
      case kTextEncodingMacDingbats:
	strcpy(cs, "adobe-fontspecific");
	break;
#endif
      default:
	strcpy(cs, "mac-roman");
	break;
      }
    }

  sprintf(xf, "-%s-%s-%s-%c-normal--%d-%d-75-75-m-%d-%s",
          foundry, family, style & bold ? "bold" : "medium",
	  style & italic ? 'i' : 'r', size, size * 10, size * 10, cs);

  result = (char *) xmalloc (strlen (xf) + 1);
  strcpy (result, xf);
  for (p = result; *p; p++)
    *p = tolower(*p);
  return result;
}


/* Convert an X font spec to the corresponding mac font name, which
   can then be passed to GetFNum after conversion to a Pascal string.
   For ordinary Mac fonts, this should just be their names, like
   "monaco", "Taipei", etc.  Fonts converted from the GNU intlfonts
   collection contain their charset designation in their names, like
   "ETL-Fixed-iso8859-1", "ETL-Fixed-koi8-r", etc.  Both types of font
   names are handled accordingly.  */
static void
x_font_name_to_mac_font_name (char *xf, char *mf)
{
  char foundry[32], family[32], weight[20], slant[2], cs[32];
  Lisp_Object coding_system = Qnil;
  struct coding_system coding;

  strcpy (mf, "");

  if (sscanf (xf, "-%31[^-]-%31[^-]-%19[^-]-%1[^-]-%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]-%31s",
              foundry, family, weight, slant, cs) != 5 &&
      sscanf (xf, "-%31[^-]-%31[^-]-%19[^-]-%1[^-]-%*[^-]--%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]-%31s",
              foundry, family, weight, slant, cs) != 5)
    return;

  if (strcmp (cs, "big5-0") == 0)
    coding_system = Qbig5;
  else if (strcmp (cs, "gb2312.1980-0") == 0)
    coding_system = Qcn_gb;
  else if (strcmp (cs, "jisx0208.1983-sjis") == 0
	   || strcmp (cs, "jisx0201.1976-0") == 0)
    coding_system = Qsjis;
  else if (strcmp (cs, "ksc5601.1989-0") == 0)
    coding_system = Qeuc_kr;
  else if (strcmp (cs, "mac-roman") == 0
	   || strcmp (cs, "mac-cyrillic") == 0
	   || strcmp (cs, "mac-centraleurroman") == 0
	   || strcmp (cs, "adobe-fontspecific") == 0)
    strcpy (mf, family);
  else
    sprintf (mf, "%s-%s-%s", foundry, family, cs);

  if (!NILP (coding_system))
    {
      setup_coding_system (coding_system, &coding);
      coding.src_multibyte = 1;
      coding.dst_multibyte = 1;
      coding.mode |= CODING_MODE_LAST_BLOCK;
      encode_coding (&coding, family, mf, strlen (family), sizeof (Str32) - 1);
      mf[coding.produced] = '\0';
    }
}


static void
add_font_name_table_entry (char *font_name)
{
  if (font_name_table_size == 0)
    {
      font_name_table_size = 16;
      font_name_table = (char **)
	xmalloc (font_name_table_size * sizeof (char *));
    }
  else if (font_name_count + 1 >= font_name_table_size)
    {
      font_name_table_size += 16;
      font_name_table = (char **)
	xrealloc (font_name_table,
		  font_name_table_size * sizeof (char *));
    }

  font_name_table[font_name_count++] = font_name;
}

/* Sets up the table font_name_table to contain the list of all fonts
   in the system the first time the table is used so that the Resource
   Manager need not be accessed every time this information is
   needed.  */

static void
init_font_name_table ()
{
#if TARGET_API_MAC_CARBON
  SInt32 sv;

  if (Gestalt (gestaltSystemVersion, &sv) == noErr && sv >= 0x1000)
    {
      FMFontFamilyIterator ffi;
      FMFontFamilyInstanceIterator ffii;
      FMFontFamily ff;

      /* Create a dummy instance iterator here to avoid creating and
	 destroying it in the loop.  */
      if (FMCreateFontFamilyInstanceIterator (0, &ffii) != noErr)
	return;
      /* Create an iterator to enumerate the font families.  */
      if (FMCreateFontFamilyIterator (NULL, NULL, kFMDefaultOptions, &ffi)
	  != noErr)
	{
	  FMDisposeFontFamilyInstanceIterator (&ffii);
	  return;
	}

      while (FMGetNextFontFamily (&ffi, &ff) == noErr)
	{
	  Str255 name;
	  FMFont font;
	  FMFontStyle style;
	  FMFontSize size;
	  TextEncoding encoding;
	  TextEncodingBase sc;

	  if (FMGetFontFamilyName (ff, name) != noErr)
	    break;
	  p2cstr (name);
	  if (*name == '.')
	    continue;

	  if (FMGetFontFamilyTextEncoding (ff, &encoding) != noErr)
	    break;
	  sc = GetTextEncodingBase (encoding);
	  decode_mac_font_name (name, sizeof (name), sc);

	  /* Point the instance iterator at the current font family.  */
	  if (FMResetFontFamilyInstanceIterator (ff, &ffii) != noErr)
	    break;

	  while (FMGetNextFontFamilyInstance (&ffii, &font, &style, &size)
		 == noErr)
	    {
	      /* Both jisx0208.1983-sjis and jisx0201.1976-0 parts are
		 contained in Apple Japanese (SJIS) font.  */
	    again:
	      if (size == 0)
		{
		  add_font_name_table_entry (mac_to_x_fontname (name, size,
								style, sc));
		  add_font_name_table_entry (mac_to_x_fontname (name, size,
								italic, sc));
		  add_font_name_table_entry (mac_to_x_fontname (name, size,
								bold, sc));
		  add_font_name_table_entry (mac_to_x_fontname (name, size,
								italic | bold,
								sc));
		}
	      else
		add_font_name_table_entry (mac_to_x_fontname (name, size,
							      style, sc));
	      if (sc == smJapanese)
		{
		  sc = -smJapanese;
		  goto again;
		}
	      else if (sc == -smJapanese)
		sc = smJapanese;
	    }
	}

      /* Dispose of the iterators.  */
      FMDisposeFontFamilyIterator (&ffi);
      FMDisposeFontFamilyInstanceIterator (&ffii);
    }
  else
    {
#endif  /* TARGET_API_MAC_CARBON */
      GrafPtr port;
      SInt16 fontnum, old_fontnum;
      int num_mac_fonts = CountResources('FOND');
      int i, j;
      Handle font_handle, font_handle_2;
      short id, scriptcode;
      ResType type;
      Str32 name;
      struct FontAssoc *fat;
      struct AsscEntry *assc_entry;

      GetPort (&port);  /* save the current font number used */
#if TARGET_API_MAC_CARBON
      old_fontnum = GetPortTextFont (port);
#else
      old_fontnum = port->txFont;
#endif

      for (i = 1; i <= num_mac_fonts; i++)  /* get all available fonts */
	{
	  font_handle = GetIndResource ('FOND', i);
	  if (!font_handle)
	    continue;

	  GetResInfo (font_handle, &id, &type, name);
	  GetFNum (name, &fontnum);
	  p2cstr (name);
	  if (fontnum == 0)
	    continue;

	  TextFont (fontnum);
	  scriptcode = FontToScript (fontnum);
	  decode_mac_font_name (name, sizeof (name), scriptcode);
	  do
	    {
	      HLock (font_handle);

	      if (GetResourceSizeOnDisk (font_handle)
		  >= sizeof (struct FamRec))
		{
		  fat = (struct FontAssoc *) (*font_handle
					      + sizeof (struct FamRec));
		  assc_entry
		    = (struct AsscEntry *) (*font_handle
					    + sizeof (struct FamRec)
					    + sizeof (struct FontAssoc));

		  for (j = 0; j <= fat->numAssoc; j++, assc_entry++)
		    {
		      if (font_name_table_size == 0)
			{
			  font_name_table_size = 16;
			  font_name_table = (char **)
			    xmalloc (font_name_table_size * sizeof (char *));
			}
		      else if (font_name_count >= font_name_table_size)
			{
			  font_name_table_size += 16;
			  font_name_table = (char **)
			    xrealloc (font_name_table,
				      font_name_table_size * sizeof (char *));
			}
		      font_name_table[font_name_count++]
			= mac_to_x_fontname (name,
					     assc_entry->fontSize,
					     assc_entry->fontStyle,
					     scriptcode);
		      /* Both jisx0208.1983-sjis and jisx0201.1976-0
			 parts are contained in Apple Japanese (SJIS)
			 font.  */
		      if (smJapanese == scriptcode)
			{
			  font_name_table[font_name_count++]
			    = mac_to_x_fontname (name,
						 assc_entry->fontSize,
						 assc_entry->fontStyle,
						 -smJapanese);
			}
		    }
		}

	      HUnlock (font_handle);
	      font_handle_2 = GetNextFOND (font_handle);
	      ReleaseResource (font_handle);
	      font_handle = font_handle_2;
	    }
	  while (ResError () == noErr && font_handle);
	}

      TextFont (old_fontnum);
#if TARGET_API_MAC_CARBON
    }
#endif  /* TARGET_API_MAC_CARBON */
}


void
mac_clear_font_name_table ()
{
  int i;

  for (i = 0; i < font_name_count; i++)
    xfree (font_name_table[i]);
  xfree (font_name_table);
  font_name_table = NULL;
  font_name_table_size = font_name_count = 0;
}


enum xlfd_scalable_field_index
  {
    XLFD_SCL_PIXEL_SIZE,
    XLFD_SCL_POINT_SIZE,
    XLFD_SCL_AVGWIDTH,
    XLFD_SCL_LAST
  };

static int xlfd_scalable_fields[] =
  {
    6,				/* PIXEL_SIZE */
    7,				/* POINT_SIZE */
    11,				/* AVGWIDTH */
    -1
  };

static Lisp_Object
mac_c_string_match (regexp, string, nonspecial, exact)
     Lisp_Object regexp;
     const char *string, *nonspecial;
     int exact;
{
  if (exact)
    {
      if (strcmp (string, nonspecial) == 0)
	return build_string (string);
    }
  else if (strstr (string, nonspecial))
    {
      Lisp_Object str = build_string (string);

      if (fast_string_match (regexp, str) >= 0)
	return str;
    }

  return Qnil;
}

static Lisp_Object
mac_do_list_fonts (pattern, maxnames)
     char *pattern;
     int maxnames;
{
  int i, n_fonts = 0;
  Lisp_Object font_list = Qnil, pattern_regex, fontname;
  char *regex = (char *) alloca (strlen (pattern) * 2 + 3);
  char scaled[256];
  char *ptr;
  int scl_val[XLFD_SCL_LAST], *field, *val;
  char *longest_start, *cur_start, *nonspecial;
  int longest_len, exact;

  if (font_name_table == NULL)  /* Initialize when first used.  */
    init_font_name_table ();

  for (i = 0; i < XLFD_SCL_LAST; i++)
    scl_val[i] = -1;

  /* If the pattern contains 14 dashes and one of PIXEL_SIZE,
     POINT_SIZE, and AVGWIDTH fields is explicitly specified, scalable
     fonts are scaled according to the specified size.  */
  ptr = pattern;
  i = 0;
  field = xlfd_scalable_fields;
  val = scl_val;
  if (*ptr == '-')
    do
      {
	ptr++;
	if (i == *field)
	  {
	    if ('1' <= *ptr && *ptr <= '9')
	      {
		*val = *ptr++ - '0';
		while ('0' <= *ptr && *ptr <= '9' && *val < 10000)
		  *val = *val * 10 + *ptr++ - '0';
		if (*ptr != '-')
		  *val = -1;
	      }
	    field++;
	    val++;
	  }
	ptr = strchr (ptr, '-');
	i++;
      }
    while (ptr && i < 14);

  if (i == 14 && ptr == NULL)
    {
      if (scl_val[XLFD_SCL_POINT_SIZE] > 0)
	{
	  scl_val[XLFD_SCL_PIXEL_SIZE] = scl_val[XLFD_SCL_POINT_SIZE] / 10;
	  scl_val[XLFD_SCL_AVGWIDTH] = scl_val[XLFD_SCL_POINT_SIZE];
	}
      else if (scl_val[XLFD_SCL_PIXEL_SIZE] > 0)
	{
	  scl_val[XLFD_SCL_POINT_SIZE] =
	    scl_val[XLFD_SCL_AVGWIDTH] = scl_val[XLFD_SCL_PIXEL_SIZE] * 10;
	}
      else if (scl_val[XLFD_SCL_AVGWIDTH] > 0)
	{
	  scl_val[XLFD_SCL_PIXEL_SIZE] = scl_val[XLFD_SCL_AVGWIDTH] / 10;
	  scl_val[XLFD_SCL_POINT_SIZE] = scl_val[XLFD_SCL_AVGWIDTH];
	}
    }
  else
    scl_val[XLFD_SCL_PIXEL_SIZE] = -1;

  ptr = regex;
  *ptr++ = '^';

  longest_start = cur_start = ptr;
  longest_len = 0;
  exact = 1;

  /* Turn pattern into a regexp and do a regexp match.  Also find the
     longest substring containing no special characters.  */
  for (; *pattern; pattern++)
    {
      if (*pattern == '?' || *pattern == '*')
	{
	  if (ptr - cur_start > longest_len)
	    {
	      longest_start = cur_start;
	      longest_len = ptr - cur_start;
	    }
	  exact = 0;

	  if (*pattern == '?')
	    *ptr++ = '.';
	  else /* if (*pattern == '*') */
	    {
	      *ptr++ = '.';
	      *ptr++ = '*';
	    }
	  cur_start = ptr;
	}
      else
	*ptr++ = tolower (*pattern);
    }

  if (ptr - cur_start > longest_len)
    {
      longest_start = cur_start;
      longest_len = ptr - cur_start;
    }

  *ptr = '$';
  *(ptr + 1) = '\0';

  nonspecial = xmalloc (longest_len + 1);
  strncpy (nonspecial, longest_start, longest_len);
  nonspecial[longest_len] = '\0';

  pattern_regex = build_string (regex);

  for (i = 0; i < font_name_count; i++)
    {
      fontname = mac_c_string_match (pattern_regex, font_name_table[i],
				     nonspecial, exact);
      if (!NILP (fontname))
	{
	  font_list = Fcons (fontname, font_list);
	  if (exact || maxnames > 0 && ++n_fonts >= maxnames)
	    break;
	}
      else if (scl_val[XLFD_SCL_PIXEL_SIZE] > 0
	       && (ptr = strstr (font_name_table[i], "-0-0-75-75-m-0-")))
	{
	  int former_len = ptr - font_name_table[i];

	  memcpy (scaled, font_name_table[i], former_len);
	  sprintf (scaled + former_len,
		   "-%d-%d-75-75-m-%d-%s",
		   scl_val[XLFD_SCL_PIXEL_SIZE],
		   scl_val[XLFD_SCL_POINT_SIZE],
		   scl_val[XLFD_SCL_AVGWIDTH],
		   ptr + sizeof ("-0-0-75-75-m-0-") - 1);
	  fontname = mac_c_string_match (pattern_regex, scaled,
					 nonspecial, exact);
	  if (!NILP (fontname))
	    {
	      font_list = Fcons (fontname, font_list);
	      if (exact || maxnames > 0 && ++n_fonts >= maxnames)
		break;
	    }
	}
    }

  xfree (nonspecial);

  return font_list;
}

/* Return a list of at most MAXNAMES font specs matching the one in
   PATTERN.  Cache matching fonts for patterns in
   dpyinfo->name_list_element to avoid looking them up again by
   calling mac_font_pattern_match (slow).  Return as many matching
   fonts as possible if MAXNAMES = -1.  */

Lisp_Object
x_list_fonts (struct frame *f,
              Lisp_Object pattern,
              int size,
              int maxnames)
{
  Lisp_Object newlist = Qnil, tem, key;
  struct mac_display_info *dpyinfo = f ? FRAME_MAC_DISPLAY_INFO (f) : NULL;

  if (dpyinfo)
    {
      tem = XCDR (dpyinfo->name_list_element);
      key = Fcons (pattern, make_number (maxnames));

      newlist = Fassoc (key, tem);
      if (!NILP (newlist))
	{
	  newlist = Fcdr_safe (newlist);
	  goto label_cached;
	}
    }

  BLOCK_INPUT;
  newlist = mac_do_list_fonts (SDATA (pattern), maxnames);
  UNBLOCK_INPUT;

  /* MAC_TODO: add code for matching outline fonts here */

  if (dpyinfo)
    {
      XSETCDR (dpyinfo->name_list_element,
	       Fcons (Fcons (key, newlist),
		      XCDR (dpyinfo->name_list_element)));
    }
 label_cached:

  return newlist;
}


#if GLYPH_DEBUG

/* Check that FONT is valid on frame F.  It is if it can be found in F's
   font table.  */

static void
x_check_font (f, font)
     struct frame *f;
     XFontStruct *font;
{
  int i;
  struct x_display_info *dpyinfo = FRAME_X_DISPLAY_INFO (f);

  xassert (font != NULL);

  for (i = 0; i < dpyinfo->n_fonts; i++)
    if (dpyinfo->font_table[i].name
	&& font == dpyinfo->font_table[i].font)
      break;

  xassert (i < dpyinfo->n_fonts);
}

#endif /* GLYPH_DEBUG != 0 */

/* Set *W to the minimum width, *H to the minimum font height of FONT.
   Note: There are (broken) X fonts out there with invalid XFontStruct
   min_bounds contents.  For example, handa@etl.go.jp reports that
   "-adobe-courier-medium-r-normal--*-180-*-*-m-*-iso8859-1" fonts
   have font->min_bounds.width == 0.  */

static INLINE void
x_font_min_bounds (font, w, h)
     MacFontStruct *font;
     int *w, *h;
{
  *h = FONT_HEIGHT (font);
  *w = font->min_bounds.width;
}


/* Compute the smallest character width and smallest font height over
   all fonts available on frame F.  Set the members smallest_char_width
   and smallest_font_height in F's x_display_info structure to
   the values computed.  Value is non-zero if smallest_font_height or
   smallest_char_width become smaller than they were before.  */

int
x_compute_min_glyph_bounds (f)
     struct frame *f;
{
  int i;
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (f);
  MacFontStruct *font;
  int old_width = dpyinfo->smallest_char_width;
  int old_height = dpyinfo->smallest_font_height;

  dpyinfo->smallest_font_height = 100000;
  dpyinfo->smallest_char_width = 100000;

  for (i = 0; i < dpyinfo->n_fonts; ++i)
    if (dpyinfo->font_table[i].name)
      {
	struct font_info *fontp = dpyinfo->font_table + i;
	int w, h;

	font = (MacFontStruct *) fontp->font;
	xassert (font != (MacFontStruct *) ~0);
	x_font_min_bounds (font, &w, &h);

	dpyinfo->smallest_font_height = min (dpyinfo->smallest_font_height, h);
	dpyinfo->smallest_char_width = min (dpyinfo->smallest_char_width, w);
      }

  xassert (dpyinfo->smallest_char_width > 0
	   && dpyinfo->smallest_font_height > 0);

  return (dpyinfo->n_fonts == 1
	  || dpyinfo->smallest_char_width < old_width
	  || dpyinfo->smallest_font_height < old_height);
}


/* Determine whether given string is a fully-specified XLFD: all 14
   fields are present, none is '*'.  */

static int
is_fully_specified_xlfd (char *p)
{
  int i;
  char *q;

  if (*p != '-')
    return 0;

  for (i = 0; i < 13; i++)
    {
      q = strchr (p + 1, '-');
      if (q == NULL)
        return 0;
      if (q - p == 2 && *(p + 1) == '*')
        return 0;
      p = q;
    }

  if (strchr (p + 1, '-') != NULL)
    return 0;

  if (*(p + 1) == '*' && *(p + 2) == '\0')
    return 0;

  return 1;
}


const int kDefaultFontSize = 9;


/* XLoadQueryFont creates and returns an internal representation for a
   font in a MacFontStruct struct.  There is really no concept
   corresponding to "loading" a font on the Mac.  But we check its
   existence and find the font number and all other information for it
   and store them in the returned MacFontStruct.  */

static MacFontStruct *
XLoadQueryFont (Display *dpy, char *fontname)
{
  int i, size, is_two_byte_font, char_width;
  char *name;
  GrafPtr port;
  SInt16 old_fontnum, old_fontsize;
  Style old_fontface;
  Str32 mfontname;
  SInt16 fontnum;
  Style fontface = normal;
  MacFontStruct *font;
  FontInfo the_fontinfo;
  char s_weight[7], c_slant;

  if (is_fully_specified_xlfd (fontname))
    name = fontname;
  else
    {
      Lisp_Object matched_fonts;

      matched_fonts = mac_do_list_fonts (fontname, 1);
      if (NILP (matched_fonts))
	return NULL;
      name = SDATA (XCAR (matched_fonts));
    }

  GetPort (&port);  /* save the current font number used */
#if TARGET_API_MAC_CARBON
  old_fontnum = GetPortTextFont (port);
  old_fontsize = GetPortTextSize (port);
  old_fontface = GetPortTextFace (port);
#else
  old_fontnum = port->txFont;
  old_fontsize = port->txSize;
  old_fontface = port->txFace;
#endif

  if (sscanf (name, "-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]--%d-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]-%*s", &size) != 1)
    size = kDefaultFontSize;

  if (sscanf (name, "-%*[^-]-%*[^-]-%6[^-]-%*c-%*[^-]--%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]-%*s", s_weight) == 1)
    if (strcmp (s_weight, "bold") == 0)
      fontface |= bold;

  if (sscanf (name, "-%*[^-]-%*[^-]-%*[^-]-%c-%*[^-]--%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]-%*s", &c_slant) == 1)
    if (c_slant == 'i')
      fontface |= italic;

  x_font_name_to_mac_font_name (name, mfontname);
  c2pstr (mfontname);
  GetFNum (mfontname, &fontnum);
  if (fontnum == 0)
    return NULL;

  font = (MacFontStruct *) xmalloc (sizeof (struct MacFontStruct));

  font->fontname = (char *) xmalloc (strlen (name) + 1);
  bcopy (name, font->fontname, strlen (name) + 1);

  font->mac_fontnum = fontnum;
  font->mac_fontsize = size;
  font->mac_fontface = fontface;
  font->mac_scriptcode = FontToScript (fontnum);

  /* Apple Japanese (SJIS) font is listed as both
     "*-jisx0208.1983-sjis" (Japanese script) and "*-jisx0201.1976-0"
     (Roman script) in init_font_name_table ().  The latter should be
     treated as a one-byte font.  */
  {
    char cs[32];

    if (sscanf (name,
		"-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]--%*[^-]-%*[^-]-%*[^-]-%*[^-]-%*c-%*[^-]-%31s",
		cs) == 1
	&& 0 == strcmp (cs, "jisx0201.1976-0"))
      font->mac_scriptcode = smRoman;
  }

  is_two_byte_font = font->mac_scriptcode == smJapanese ||
                     font->mac_scriptcode == smTradChinese ||
                     font->mac_scriptcode == smSimpChinese ||
                     font->mac_scriptcode == smKorean;

  TextFont (fontnum);
  TextSize (size);
  TextFace (fontface);

  GetFontInfo (&the_fontinfo);

  font->ascent = the_fontinfo.ascent;
  font->descent = the_fontinfo.descent;

  font->min_byte1 = 0;
  if (is_two_byte_font)
    font->max_byte1 = 1;
  else
    font->max_byte1 = 0;
  font->min_char_or_byte2 = 0x20;
  font->max_char_or_byte2 = 0xff;

  if (is_two_byte_font)
    {
      /* Use the width of an "ideographic space" of that font because
         the_fontinfo.widMax returns the wrong width for some fonts.  */
      switch (font->mac_scriptcode)
        {
        case smJapanese:
          char_width = StringWidth("\p\x81\x40");
          break;
        case smTradChinese:
          char_width = StringWidth("\p\xa1\x40");
          break;
        case smSimpChinese:
          char_width = StringWidth("\p\xa1\xa1");
          break;
        case smKorean:
          char_width = StringWidth("\p\xa1\xa1");
          break;
        }
    }
  else
    /* Do this instead of use the_fontinfo.widMax, which incorrectly
       returns 15 for 12-point Monaco! */
    char_width = CharWidth ('m');

  if (is_two_byte_font)
    {
      font->per_char = NULL;

      if (fontface & italic)
	font->max_bounds.rbearing = char_width + 1;
      else
	font->max_bounds.rbearing = char_width;
      font->max_bounds.lbearing = 0;
      font->max_bounds.width = char_width;
      font->max_bounds.ascent = the_fontinfo.ascent;
      font->max_bounds.descent = the_fontinfo.descent;

      font->min_bounds = font->max_bounds;
    }
  else
    {
      font->per_char = (XCharStruct *)
	xmalloc (sizeof (XCharStruct) * (0xff - 0x20 + 1));
      {
	int c, min_width, max_width;
	Rect char_bounds, min_bounds, max_bounds;
	char ch;

	min_width = max_width = char_width;
	SetRect (&min_bounds, -32767, -32767, 32767, 32767);
	SetRect (&max_bounds, 0, 0, 0, 0);
        for (c = 0x20; c <= 0xff; c++)
          {
	    ch = c;
	    char_width = CharWidth (ch);
	    QDTextBounds (1, &ch, &char_bounds);
	    STORE_XCHARSTRUCT (font->per_char[c - 0x20],
			       char_width, char_bounds);
	    /* Some Japanese fonts (in SJIS encoding) return 0 as the
	       character width of 0x7f.  */
	    if (char_width > 0)
	      {
		min_width = min (min_width, char_width);
		max_width = max (max_width, char_width);
	      }
	    if (!EmptyRect (&char_bounds))
	      {
		SetRect (&min_bounds,
			 max (min_bounds.left, char_bounds.left),
			 max (min_bounds.top, char_bounds.top),
			 min (min_bounds.right, char_bounds.right),
			 min (min_bounds.bottom, char_bounds.bottom));
		UnionRect (&max_bounds, &char_bounds, &max_bounds);
	      }
	  }
	STORE_XCHARSTRUCT (font->min_bounds, min_width, min_bounds);
	STORE_XCHARSTRUCT (font->max_bounds, max_width, max_bounds);
	if (min_width == max_width
	    && max_bounds.left >= 0 && max_bounds.right <= max_width)
	  {
	    /* Fixed width and no overhangs.  */
	    xfree (font->per_char);
	    font->per_char = NULL;
	  }
      }
    }

  TextFont (old_fontnum);  /* restore previous font number, size and face */
  TextSize (old_fontsize);
  TextFace (old_fontface);

  return font;
}


void
mac_unload_font (dpyinfo, font)
     struct mac_display_info *dpyinfo;
     XFontStruct *font;
{
  xfree (font->fontname);
  if (font->per_char)
    xfree (font->per_char);
  xfree (font);
}


/* Load font named FONTNAME of the size SIZE for frame F, and return a
   pointer to the structure font_info while allocating it dynamically.
   If SIZE is 0, load any size of font.
   If loading is failed, return NULL.  */

struct font_info *
x_load_font (f, fontname, size)
     struct frame *f;
     register char *fontname;
     int size;
{
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (f);
  Lisp_Object font_names;

  /* Get a list of all the fonts that match this name.  Once we
     have a list of matching fonts, we compare them against the fonts
     we already have by comparing names.  */
  font_names = x_list_fonts (f, build_string (fontname), size, 1);

  if (!NILP (font_names))
    {
      Lisp_Object tail;
      int i;

      for (i = 0; i < dpyinfo->n_fonts; i++)
	for (tail = font_names; CONSP (tail); tail = XCDR (tail))
	  if (dpyinfo->font_table[i].name
	      && (!strcmp (dpyinfo->font_table[i].name,
			   SDATA (XCAR (tail)))
		  || !strcmp (dpyinfo->font_table[i].full_name,
			      SDATA (XCAR (tail)))))
	    return (dpyinfo->font_table + i);
    }

  /* Load the font and add it to the table.  */
  {
    char *full_name;
    struct MacFontStruct *font;
    struct font_info *fontp;
    unsigned long value;
    int i;

    /* If we have found fonts by x_list_font, load one of them.  If
       not, we still try to load a font by the name given as FONTNAME
       because XListFonts (called in x_list_font) of some X server has
       a bug of not finding a font even if the font surely exists and
       is loadable by XLoadQueryFont.  */
    if (size > 0 && !NILP (font_names))
      fontname = (char *) SDATA (XCAR (font_names));

    BLOCK_INPUT;
    font = (MacFontStruct *) XLoadQueryFont (FRAME_MAC_DISPLAY (f), fontname);
    UNBLOCK_INPUT;
    if (!font)
      return NULL;

    /* Find a free slot in the font table.  */
    for (i = 0; i < dpyinfo->n_fonts; ++i)
      if (dpyinfo->font_table[i].name == NULL)
	break;

    /* If no free slot found, maybe enlarge the font table.  */
    if (i == dpyinfo->n_fonts
	&& dpyinfo->n_fonts == dpyinfo->font_table_size)
      {
	int sz;
	dpyinfo->font_table_size = max (16, 2 * dpyinfo->font_table_size);
	sz = dpyinfo->font_table_size * sizeof *dpyinfo->font_table;
	dpyinfo->font_table
	  = (struct font_info *) xrealloc (dpyinfo->font_table, sz);
      }

    fontp = dpyinfo->font_table + i;
    if (i == dpyinfo->n_fonts)
      ++dpyinfo->n_fonts;

    /* Now fill in the slots of *FONTP.  */
    BLOCK_INPUT;
    bzero (fontp, sizeof (*fontp));
    fontp->font = font;
    fontp->font_idx = i;
    fontp->name = (char *) xmalloc (strlen (font->fontname) + 1);
    bcopy (font->fontname, fontp->name, strlen (font->fontname) + 1);

    if (font->min_bounds.width == font->max_bounds.width)
      {
	/* Fixed width font.  */
	fontp->average_width = fontp->space_width = font->min_bounds.width;
      }
    else
      {
	XChar2b char2b;
	XCharStruct *pcm;

	char2b.byte1 = 0x00, char2b.byte2 = 0x20;
	pcm = mac_per_char_metric (font, &char2b, 0);
	if (pcm)
	  fontp->space_width = pcm->width;
	else
	  fontp->space_width = FONT_WIDTH (font);

	if (pcm)
	  {
	    int width = pcm->width;
	    for (char2b.byte2 = 33; char2b.byte2 <= 126; char2b.byte2++)
	      if ((pcm = mac_per_char_metric (font, &char2b, 0)) != NULL)
		width += pcm->width;
	    fontp->average_width = width / 95;
	  }
	else
	  fontp->average_width = FONT_WIDTH (font);
      }

    fontp->full_name = fontp->name;

    fontp->size = font->max_bounds.width;
    fontp->height = FONT_HEIGHT (font);
    {
      /* For some font, ascent and descent in max_bounds field is
	 larger than the above value.  */
      int max_height = font->max_bounds.ascent + font->max_bounds.descent;
      if (max_height > fontp->height)
	fontp->height = max_height;
    }

    /* The slot `encoding' specifies how to map a character
       code-points (0x20..0x7F or 0x2020..0x7F7F) of each charset to
       the font code-points (0:0x20..0x7F, 1:0xA0..0xFF), or
       (0:0x2020..0x7F7F, 1:0xA0A0..0xFFFF, 3:0x20A0..0x7FFF,
       2:0xA020..0xFF7F).  For the moment, we don't know which charset
       uses this font.  So, we set information in fontp->encoding[1]
       which is never used by any charset.  If mapping can't be
       decided, set FONT_ENCODING_NOT_DECIDED.  */
    if (font->mac_scriptcode == smJapanese)
      fontp->encoding[1] = 4;
    else
      {
        fontp->encoding[1]
           = (font->max_byte1 == 0
	      /* 1-byte font */
	      ? (font->min_char_or_byte2 < 0x80
	         ? (font->max_char_or_byte2 < 0x80
	            ? 0		/* 0x20..0x7F */
	            : FONT_ENCODING_NOT_DECIDED) /* 0x20..0xFF */
	         : 1)		/* 0xA0..0xFF */
	      /* 2-byte font */
	      : (font->min_byte1 < 0x80
	         ? (font->max_byte1 < 0x80
	            ? (font->min_char_or_byte2 < 0x80
		       ? (font->max_char_or_byte2 < 0x80
		          ? 0		/* 0x2020..0x7F7F */
		          : FONT_ENCODING_NOT_DECIDED) /* 0x2020..0x7FFF */
		       : 3)		/* 0x20A0..0x7FFF */
	            : FONT_ENCODING_NOT_DECIDED) /* 0x20??..0xA0?? */
	         : (font->min_char_or_byte2 < 0x80
	            ? (font->max_char_or_byte2 < 0x80
		       ? 2		/* 0xA020..0xFF7F */
		       : FONT_ENCODING_NOT_DECIDED) /* 0xA020..0xFFFF */
	            : 1)));		/* 0xA0A0..0xFFFF */
      }

#if 0 /* MAC_TODO: fill these out with more reasonably values */
    fontp->baseline_offset
      = (XGetFontProperty (font, dpyinfo->Xatom_MULE_BASELINE_OFFSET, &value)
	 ? (long) value : 0);
    fontp->relative_compose
      = (XGetFontProperty (font, dpyinfo->Xatom_MULE_RELATIVE_COMPOSE, &value)
	 ? (long) value : 0);
    fontp->default_ascent
      = (XGetFontProperty (font, dpyinfo->Xatom_MULE_DEFAULT_ASCENT, &value)
	 ? (long) value : 0);
#else
    fontp->baseline_offset = 0;
    fontp->relative_compose = 0;
    fontp->default_ascent = 0;
#endif

    /* Set global flag fonts_changed_p to non-zero if the font loaded
       has a character with a smaller width than any other character
       before, or if the font loaded has a smalle>r height than any
       other font loaded before.  If this happens, it will make a
       glyph matrix reallocation necessary.  */
    fonts_changed_p = x_compute_min_glyph_bounds (f);
    UNBLOCK_INPUT;
    return fontp;
  }
}


/* Return a pointer to struct font_info of a font named FONTNAME for
   frame F.  If no such font is loaded, return NULL.  */

struct font_info *
x_query_font (f, fontname)
     struct frame *f;
     register char *fontname;
{
  struct mac_display_info *dpyinfo = FRAME_MAC_DISPLAY_INFO (f);
  int i;

  for (i = 0; i < dpyinfo->n_fonts; i++)
    if (dpyinfo->font_table[i].name
	&& (!strcmp (dpyinfo->font_table[i].name, fontname)
	    || !strcmp (dpyinfo->font_table[i].full_name, fontname)))
      return (dpyinfo->font_table + i);
  return NULL;
}


/* Find a CCL program for a font specified by FONTP, and set the member
 `encoder' of the structure.  */

void
x_find_ccl_program (fontp)
     struct font_info *fontp;
{
  Lisp_Object list, elt;

  for (list = Vfont_ccl_encoder_alist; CONSP (list); list = XCDR (list))
    {
      elt = XCAR (list);
      if (CONSP (elt)
	  && STRINGP (XCAR (elt))
	  && (fast_c_string_match_ignore_case (XCAR (elt), fontp->name)
	      >= 0))
	break;
    }
  if (! NILP (list))
    {
      struct ccl_program *ccl
	= (struct ccl_program *) xmalloc (sizeof (struct ccl_program));

      if (setup_ccl_program (ccl, XCDR (elt)) < 0)
	xfree (ccl);
      else
	fontp->font_encoder = ccl;
    }
}



/* The Mac Event loop code */

#if !TARGET_API_MAC_CARBON
#include <Events.h>
#include <Quickdraw.h>
#include <Balloons.h>
#include <Devices.h>
#include <Fonts.h>
#include <Gestalt.h>
#include <Menus.h>
#include <Processes.h>
#include <Sound.h>
#include <ToolUtils.h>
#include <TextUtils.h>
#include <Dialogs.h>
#include <Script.h>
#include <Types.h>
#include <TextEncodingConverter.h>
#include <Resources.h>

#if __MWERKS__
#include <unix.h>
#endif
#endif /* ! TARGET_API_MAC_CARBON */

#define M_APPLE 128
#define I_ABOUT 1

#define WINDOW_RESOURCE 128
#define TERM_WINDOW_RESOURCE 129

#define DEFAULT_NUM_COLS 80

#define MIN_DOC_SIZE 64
#define MAX_DOC_SIZE 32767

/* sleep time for WaitNextEvent */
#define WNE_SLEEP_AT_SUSPEND 10
#define WNE_SLEEP_AT_RESUME  1

/* true when cannot handle any Mac OS events */
static int handling_window_update = 0;

#if 0
/* the flag appl_is_suspended is used both for determining the sleep
   time to be passed to WaitNextEvent and whether the cursor should be
   drawn when updating the display.  The cursor is turned off when
   Emacs is suspended.  Redrawing it is unnecessary and what needs to
   be done depends on whether the cursor lies inside or outside the
   redraw region.  So we might as well skip drawing it when Emacs is
   suspended.  */
static Boolean app_is_suspended = false;
static long app_sleep_time = WNE_SLEEP_AT_RESUME;
#endif

#define EXTRA_STACK_ALLOC (256 * 1024)

#define ARGV_STRING_LIST_ID 129
#define ABOUT_ALERT_ID	128
#define RAM_TOO_LARGE_ALERT_ID 129

Boolean	terminate_flag = false;

/* Contains the string "reverse", which is a constant for mouse button emu.*/
Lisp_Object Qreverse;

/* True if using command key as meta key.  */
Lisp_Object Vmac_command_key_is_meta;

/* Modifier associated with the option key, or nil for normal behavior. */
Lisp_Object Vmac_option_modifier;

/* True if the ctrl and meta keys should be reversed.  */
Lisp_Object Vmac_reverse_ctrl_meta;

/* True if the option and command modifiers should be used to emulate
   a three button mouse */
Lisp_Object Vmac_emulate_three_button_mouse;

#if USE_CARBON_EVENTS
/* True if the mouse wheel button (i.e. button 4) should map to
   mouse-2, instead of mouse-3.  */
Lisp_Object Vmac_wheel_button_is_mouse_2;

/* If Non-nil, the Mac "Command" key is passed on to the Mac Toolbox
   for processing before Emacs sees it.  */
Lisp_Object Vmac_pass_command_to_system;

/* If Non-nil, the Mac "Control" key is passed on to the Mac Toolbox
   for processing before Emacs sees it.  */
Lisp_Object Vmac_pass_control_to_system;
#endif

/* convert input from Mac keyboard (assumed to be in Mac Roman coding)
   to this text encoding */
int mac_keyboard_text_encoding;
int current_mac_keyboard_text_encoding = kTextEncodingMacRoman;

/* Set in term/mac-win.el to indicate that event loop can now generate
   drag and drop events.  */
Lisp_Object Qmac_ready_for_drag_n_drop;

Lisp_Object drag_and_drop_file_list;

Point saved_menu_event_location;

#if !TARGET_API_MAC_CARBON
/* Place holder for the default arrow cursor.  */
CursPtr arrow_cursor;
#endif

/* Apple Events */
static void init_required_apple_events (void);
static pascal OSErr
do_ae_open_application (const AppleEvent *, AppleEvent *, long);
static pascal OSErr
do_ae_print_documents (const AppleEvent *, AppleEvent *, long);
static pascal OSErr do_ae_open_documents (AppleEvent *, AppleEvent *, long);
static pascal OSErr do_ae_quit_application (AppleEvent *, AppleEvent *, long);

#if TARGET_API_MAC_CARBON
/* Drag and Drop */
static pascal OSErr mac_do_track_drag (DragTrackingMessage, WindowPtr, void*, DragReference);
static pascal OSErr mac_do_receive_drag (WindowPtr, void*, DragReference);
static DragTrackingHandlerUPP mac_do_track_dragUPP = NULL;
static DragReceiveHandlerUPP mac_do_receive_dragUPP = NULL;
#endif

#if USE_CARBON_EVENTS
#ifdef MAC_OSX
/* Preliminary Support for the OSX Services Menu */
static OSStatus mac_handle_service_event (EventHandlerCallRef,EventRef,void*);
static void init_service_handler ();
#endif
/* Window Event Handler */
static pascal OSStatus mac_handle_window_event (EventHandlerCallRef,
						EventRef, void *);
#endif
OSErr install_window_handler (WindowPtr);

extern void init_emacs_passwd_dir ();
extern int emacs_main (int, char **, char **);
extern void check_alarm ();

extern void initialize_applescript();
extern void terminate_applescript();

static unsigned int
#if USE_CARBON_EVENTS
mac_to_emacs_modifiers (UInt32 mods)
#else
mac_to_emacs_modifiers (EventModifiers mods)
#endif
{
  unsigned int result = 0;
  if (mods & macShiftKey)
    result |= shift_modifier;
  if (mods & macCtrlKey)
    result |= ctrl_modifier;
  if (mods & macMetaKey)
    result |= meta_modifier;
  if (NILP (Vmac_command_key_is_meta) && (mods & macAltKey))
    result |= alt_modifier;
  if (!NILP (Vmac_option_modifier) && (mods & optionKey)) {
      Lisp_Object val = Fget(Vmac_option_modifier, Qmodifier_value);
      if (!NILP(val))
          result |= XUINT(val);
  }

  return result;
}

static int
mac_get_emulated_btn ( UInt32 modifiers )
{
  int result = 0;
  if (!NILP (Vmac_emulate_three_button_mouse)) {
    int cmdIs3 = !EQ (Vmac_emulate_three_button_mouse, Qreverse);
    if (modifiers & cmdKey)
      result = cmdIs3 ? 2 : 1;
    else if (modifiers & optionKey)
      result = cmdIs3 ? 1 : 2;
  }
  return result;
}

#if USE_CARBON_EVENTS
/* Obtains the event modifiers from the event ref and then calls
   mac_to_emacs_modifiers.  */
static int
mac_event_to_emacs_modifiers (EventRef eventRef)
{
  UInt32 mods = 0;
  GetEventParameter (eventRef, kEventParamKeyModifiers, typeUInt32, NULL,
		    sizeof (UInt32), NULL, &mods);
  if (!NILP (Vmac_emulate_three_button_mouse) &&
      GetEventClass(eventRef) == kEventClassMouse)
    {
      mods &= ~(optionKey | cmdKey);
    }
  return mac_to_emacs_modifiers (mods);
}

/* Given an event ref, return the code to use for the mouse button
   code in the emacs input_event.  */
static int
mac_get_mouse_btn (EventRef ref)
{
  EventMouseButton result = kEventMouseButtonPrimary;
  GetEventParameter (ref, kEventParamMouseButton, typeMouseButton, NULL,
		    sizeof (EventMouseButton), NULL, &result);
  switch (result)
    {
    case kEventMouseButtonPrimary:
      if (NILP (Vmac_emulate_three_button_mouse))
	return 0;
      else {
	UInt32 mods = 0;
	GetEventParameter (ref, kEventParamKeyModifiers, typeUInt32, NULL,
			   sizeof (UInt32), NULL, &mods);
	return mac_get_emulated_btn(mods);
      }
    case kEventMouseButtonSecondary:
      return NILP (Vmac_wheel_button_is_mouse_2) ? 1 : 2;
    case kEventMouseButtonTertiary:
    case 4:  /* 4 is the number for the mouse wheel button */
      return NILP (Vmac_wheel_button_is_mouse_2) ? 2 : 1;
    default:
      return 0;
    }
}

/* Normally, ConvertEventRefToEventRecord will correctly handle all
   events.  However the click of the mouse wheel is not converted to a
   mouseDown or mouseUp event.  This calls ConvertEventRef, but then
   checks to see if it is a mouse up or down carbon event that has not
   been converted, and if so, converts it by hand (to be picked up in
   the XTread_socket loop).  */
static Boolean mac_convert_event_ref (EventRef eventRef, EventRecord *eventRec)
{
  Boolean result = ConvertEventRefToEventRecord (eventRef, eventRec);
  /* Do special case for mouse wheel button.  */
  if (!result && GetEventClass (eventRef) == kEventClassMouse)
    {
      UInt32 kind = GetEventKind (eventRef);
      if (kind == kEventMouseDown && !(eventRec->what == mouseDown))
	{
	  eventRec->what = mouseDown;
	  result=1;
	}
      if (kind == kEventMouseUp && !(eventRec->what == mouseUp))
	{
	  eventRec->what = mouseUp;
	  result=1;
	}
      if (result)
	{
	  /* Need where and when.  */
	  UInt32 mods;
	  GetEventParameter (eventRef, kEventParamMouseLocation,
			     typeQDPoint, NULL, sizeof (Point),
			     NULL, &eventRec->where);
	  /* Use two step process because new event modifiers are
	     32-bit and old are 16-bit.  Currently, only loss is
	     NumLock & Fn. */
	  GetEventParameter (eventRef, kEventParamKeyModifiers,
			     typeUInt32, NULL, sizeof (UInt32),
			     NULL, &mods);
	  eventRec->modifiers = mods;

	  eventRec->when = EventTimeToTicks (GetEventTime (eventRef));
	}
    }
  return result;
}

#endif

static void
do_get_menus (void)
{
  Handle menubar_handle;
  MenuHandle menu_handle;

  menubar_handle = GetNewMBar (128);
  if(menubar_handle == NULL)
    abort ();
  SetMenuBar (menubar_handle);
  DrawMenuBar ();

  menu_handle = GetMenuHandle (M_APPLE);
  if(menu_handle != NULL)
    AppendResMenu (menu_handle,'DRVR');
  else
    abort ();
}


static void
do_init_managers (void)
{
#if !TARGET_API_MAC_CARBON
  InitGraf (&qd.thePort);
  InitFonts ();
  FlushEvents (everyEvent, 0);
  InitWindows ();
  InitMenus ();
  TEInit ();
  InitDialogs (NULL);
#endif /* !TARGET_API_MAC_CARBON */
  InitCursor ();

#if !TARGET_API_MAC_CARBON
  arrow_cursor = &qd.arrow;

  /* set up some extra stack space for use by emacs */
  SetApplLimit ((Ptr) ((long) GetApplLimit () - EXTRA_STACK_ALLOC));

  /* MaxApplZone must be called for AppleScript to execute more
     complicated scripts */
  MaxApplZone ();
  MoreMasters ();
#endif /* !TARGET_API_MAC_CARBON */
}

static void
do_check_ram_size (void)
{
  SInt32 physical_ram_size, logical_ram_size;

  if (Gestalt (gestaltPhysicalRAMSize, &physical_ram_size) != noErr
      || Gestalt (gestaltLogicalRAMSize, &logical_ram_size) != noErr
      || physical_ram_size > (1 << VALBITS)
      || logical_ram_size > (1 << VALBITS))
    {
      StopAlert (RAM_TOO_LARGE_ALERT_ID, NULL);
      exit (1);
    }
}

static void
do_window_update (WindowPtr win)
{
  struct frame *f = mac_window_to_frame (win);

  BeginUpdate (win);

  /* The tooltip has been drawn already.  Avoid the SET_FRAME_GARBAGED
     below.  */
  if (win != tip_window)
    {
      if (f->async_visible == 0)
        {
          f->async_visible = 1;
          f->async_iconified = 0;
          SET_FRAME_GARBAGED (f);

          /* An update event is equivalent to MapNotify on X, so report
             visibility changes properly.  */
          if (! NILP(Vframe_list) && ! NILP (XCDR (Vframe_list)))
            /* Force a redisplay sooner or later to update the
               frame titles in case this is the second frame.  */
            record_asynch_buffer_change ();
        }
      else
        {
	  Rect r;

          handling_window_update = 1;

#if TARGET_API_MAC_CARBON
	  {
	    RgnHandle region = NewRgn ();

	    GetPortVisibleRegion (GetWindowPort (win), region);
	    UpdateControls (win, region);
	    GetRegionBounds (region, &r);
	    DisposeRgn (region);
	  }
#else
	  UpdateControls (win, win->visRgn);
	  r = (*win->visRgn)->rgnBBox;
#endif
	  expose_frame (f, r.left, r.top, r.right - r.left, r.bottom - r.top);

          handling_window_update = 0;
        }
    }

  EndUpdate (win);
}

static int
is_emacs_window (WindowPtr win)
{
  Lisp_Object tail, frame;

  if (!win)
    return 0;

  FOR_EACH_FRAME (tail, frame)
    if (FRAME_MAC_P (XFRAME (frame)))
      if (FRAME_MAC_WINDOW (XFRAME (frame)) == win)
	return 1;

  return 0;
}

static void
do_app_resume ()
{
  /* Window-activate events will do the job. */
#if 0
  WindowPtr wp;
  struct frame *f;

  wp = front_emacs_window ();
  if (wp)
    {
      f = mac_window_to_frame (wp);

      if (f)
	{
	  x_new_focus_frame (FRAME_MAC_DISPLAY_INFO (f), f);
	  activate_scroll_bars (f);
	}
    }

  app_is_suspended = false;
  app_sleep_time = WNE_SLEEP_AT_RESUME;
#endif
}

static void
do_app_suspend ()
{
  /* Window-deactivate events will do the job. */
#if 0
  WindowPtr wp;
  struct frame *f;

  wp = front_emacs_window ();
  if (wp)
    {
      f = mac_window_to_frame (wp);

      if (f == FRAME_MAC_DISPLAY_INFO (f)->x_focus_frame)
	{
	  x_new_focus_frame (FRAME_MAC_DISPLAY_INFO (f), 0);
	  deactivate_scroll_bars (f);
	}
    }

  app_is_suspended = true;
  app_sleep_time = WNE_SLEEP_AT_SUSPEND;
#endif
}


static void
do_mouse_moved (mouse_pos, f)
     Point mouse_pos;
     FRAME_PTR *f;
{
  WindowPtr wp = front_emacs_window ();
  struct x_display_info *dpyinfo;

  if (wp)
    {
      *f = mac_window_to_frame (wp);
      dpyinfo = FRAME_MAC_DISPLAY_INFO (*f);

      if (dpyinfo->mouse_face_hidden)
	{
	  dpyinfo->mouse_face_hidden = 0;
	  clear_mouse_face (dpyinfo);
	}

      SetPortWindowPort (wp);

      GlobalToLocal (&mouse_pos);

      if (dpyinfo->grabbed && tracked_scroll_bar)
	x_scroll_bar_note_movement (tracked_scroll_bar,
				    mouse_pos.v
				    - XINT (tracked_scroll_bar->top),
				    TickCount() * (1000 / 60));
      else
	note_mouse_movement (*f, &mouse_pos);
    }
}


static void
do_apple_menu (SInt16 menu_item)
{
#if !TARGET_API_MAC_CARBON
  Str255 item_name;
  SInt16 da_driver_refnum;

  if (menu_item == I_ABOUT)
    NoteAlert (ABOUT_ALERT_ID, NULL);
  else
    {
      GetMenuItemText (GetMenuHandle (M_APPLE), menu_item, item_name);
      da_driver_refnum = OpenDeskAcc (item_name);
    }
#endif /* !TARGET_API_MAC_CARBON */
}

void
do_menu_choice (SInt32 menu_choice)
{
  SInt16 menu_id, menu_item;

  menu_id = HiWord (menu_choice);
  menu_item = LoWord (menu_choice);

  if (menu_id == 0)
    return;

  switch (menu_id)
    {
    case M_APPLE:
      do_apple_menu (menu_item);
      break;

    default:
      {
        struct frame *f = mac_window_to_frame (front_emacs_window ());
        MenuHandle menu = GetMenuHandle (menu_id);
        if (menu)
          {
            UInt32 refcon;

            GetMenuItemRefCon (menu, menu_item, &refcon);
            menubar_selection_callback (f, refcon);
          }
      }
    }

  HiliteMenu (0);
}


/* Handle drags in size box.  Based on code contributed by Ben
   Mesander and IM - Window Manager A.  */

static void
do_grow_window (WindowPtr w, EventRecord *e)
{
  Rect limit_rect;
  int rows, columns, width, height;
  struct frame *f = mac_window_to_frame (w);
  XSizeHints *size_hints = FRAME_SIZE_HINTS (f);
  int min_width = MIN_DOC_SIZE, min_height = MIN_DOC_SIZE;
#if TARGET_API_MAC_CARBON
  Rect new_rect;
#else
  long grow_size;
#endif

  if (size_hints->flags & PMinSize)
    {
      min_width  = size_hints->min_width;
      min_height = size_hints->min_height;
    }
  SetRect (&limit_rect, min_width, min_height, MAX_DOC_SIZE, MAX_DOC_SIZE);

#if TARGET_API_MAC_CARBON
  if (!ResizeWindow (w, e->where, &limit_rect, &new_rect))
    return;
  height = new_rect.bottom - new_rect.top;
  width = new_rect.right - new_rect.left;
#else
  grow_size = GrowWindow (w, e->where, &limit_rect);
  /* see if it really changed size */
  if (grow_size == 0)
    return;
  height = HiWord (grow_size);
  width = LoWord (grow_size);
#endif

  if (width != FRAME_PIXEL_WIDTH (f)
      || height != FRAME_PIXEL_HEIGHT (f))
    {
      rows = FRAME_PIXEL_HEIGHT_TO_TEXT_LINES (f, height);
      columns = FRAME_PIXEL_WIDTH_TO_TEXT_COLS (f, width);

      x_set_window_size (f, 0, columns, rows);
    }
}


/* Handle clicks in zoom box.  Calculation of "standard state" based
   on code in IM - Window Manager A and code contributed by Ben
   Mesander.  The standard state of an Emacs window is 80-characters
   wide (DEFAULT_NUM_COLS) and as tall as will fit on the screen.  */

static void
do_zoom_window (WindowPtr w, int zoom_in_or_out)
{
  GrafPtr save_port;
  Rect zoom_rect, port_rect;
  Point top_left;
  int w_title_height, columns, rows, width, height;
  struct frame *f = mac_window_to_frame (w);

#if TARGET_API_MAC_CARBON
  {
    Point standard_size;

    standard_size.h = FRAME_TEXT_COLS_TO_PIXEL_WIDTH (f, DEFAULT_NUM_COLS);
    standard_size.v = FRAME_MAC_DISPLAY_INFO (f)->height;

    if (IsWindowInStandardState (w, &standard_size, &zoom_rect))
      zoom_in_or_out = inZoomIn;
    else
      {
	/* Adjust the standard size according to character boundaries.  */

	columns = FRAME_PIXEL_WIDTH_TO_TEXT_COLS (f, zoom_rect.right - zoom_rect.left);
	rows = FRAME_PIXEL_HEIGHT_TO_TEXT_LINES (f, zoom_rect.bottom - zoom_rect.top);
	standard_size.h = FRAME_TEXT_COLS_TO_PIXEL_WIDTH (f, columns);
	standard_size.v = FRAME_TEXT_LINES_TO_PIXEL_HEIGHT (f, rows);
	GetWindowBounds (w, kWindowContentRgn, &port_rect);
	if (IsWindowInStandardState (w, &standard_size, &zoom_rect)
	    && port_rect.left == zoom_rect.left
	    && port_rect.top == zoom_rect.top)
	  zoom_in_or_out = inZoomIn;
	else
	  zoom_in_or_out = inZoomOut;
      }

    ZoomWindowIdeal (w, zoom_in_or_out, &standard_size);
  }
#else /* not TARGET_API_MAC_CARBON */
  GetPort (&save_port);

  SetPortWindowPort (w);

  /* Clear window to avoid flicker.  */
  EraseRect (&(w->portRect));
  if (zoom_in_or_out == inZoomOut)
    {
      SetPt (&top_left, w->portRect.left, w->portRect.top);
      LocalToGlobal (&top_left);

      /* calculate height of window's title bar */
      w_title_height = top_left.v - 1
	- (**((WindowPeek) w)->strucRgn).rgnBBox.top + GetMBarHeight ();

      /* get maximum height of window into zoom_rect.bottom - zoom_rect.top */
      zoom_rect = qd.screenBits.bounds;
      zoom_rect.top += w_title_height;
      InsetRect (&zoom_rect, 8, 4);  /* not too tight */

      zoom_rect.right = zoom_rect.left
	+ FRAME_TEXT_COLS_TO_PIXEL_WIDTH (f, DEFAULT_NUM_COLS);

      /* Adjust the standard size according to character boundaries.  */
      rows = FRAME_PIXEL_HEIGHT_TO_TEXT_LINES (f, zoom_rect.bottom - zoom_rect.top);
      zoom_rect.bottom =
	zoom_rect.top + FRAME_TEXT_LINES_TO_PIXEL_HEIGHT (f, rows);

      (**((WStateDataHandle) ((WindowPeek) w)->dataHandle)).stdState
	= zoom_rect;
    }

  ZoomWindow (w, zoom_in_or_out, w == front_emacs_window ());

  SetPort (save_port);
#endif /* not TARGET_API_MAC_CARBON */

  /* retrieve window size and update application values */
#if TARGET_API_MAC_CARBON
  GetWindowPortBounds (w, &port_rect);
#else
  port_rect = w->portRect;
#endif
  height = port_rect.bottom - port_rect.top;
  width = port_rect.right - port_rect.left;

  if (width != FRAME_PIXEL_WIDTH (f)
      || height != FRAME_PIXEL_HEIGHT (f))
    {
      rows = FRAME_PIXEL_HEIGHT_TO_TEXT_LINES (f, height);
      columns = FRAME_PIXEL_WIDTH_TO_TEXT_COLS (f, width);

      change_frame_size (f, rows, columns, 0, 1, 0);
      SET_FRAME_GARBAGED (f);
      cancel_mouse_face (f);

      FRAME_PIXEL_WIDTH (f) = width;
      FRAME_PIXEL_HEIGHT (f) = height;
    }
  x_real_positions (f, &f->left_pos, &f->top_pos);
}

/* Intialize AppleEvent dispatcher table for the required events.  */
void
init_required_apple_events ()
{
  OSErr err;
  long result;

  /* Make sure we have apple events before starting.  */
  err = Gestalt (gestaltAppleEventsAttr, &result);
  if (err != noErr)
    abort ();

  if (!(result & (1 << gestaltAppleEventsPresent)))
    abort ();

#if TARGET_API_MAC_CARBON
  err = AEInstallEventHandler(kCoreEventClass, kAEOpenApplication,
			      NewAEEventHandlerUPP
			      ((AEEventHandlerProcPtr) do_ae_open_application),
                              0L, false);
#else
  err = AEInstallEventHandler(kCoreEventClass, kAEOpenApplication,
			      NewAEEventHandlerProc
			      ((AEEventHandlerProcPtr) do_ae_open_application),
                              0L, false);
#endif
  if (err != noErr)
    abort ();

#if TARGET_API_MAC_CARBON
  err = AEInstallEventHandler(kCoreEventClass, kAEOpenDocuments,
                              NewAEEventHandlerUPP
			      ((AEEventHandlerProcPtr) do_ae_open_documents),
                              0L, false);
#else
  err = AEInstallEventHandler(kCoreEventClass, kAEOpenDocuments,
                              NewAEEventHandlerProc
			      ((AEEventHandlerProcPtr) do_ae_open_documents),
                              0L, false);
#endif
  if (err != noErr)
    abort ();

#if TARGET_API_MAC_CARBON
  err = AEInstallEventHandler(kCoreEventClass, kAEPrintDocuments,
                              NewAEEventHandlerUPP
			      ((AEEventHandlerProcPtr) do_ae_print_documents),
                              0L, false);
#else
  err = AEInstallEventHandler(kCoreEventClass, kAEPrintDocuments,
                              NewAEEventHandlerProc
			      ((AEEventHandlerProcPtr) do_ae_print_documents),
                              0L, false);
#endif
  if (err != noErr)
    abort ();

#if TARGET_API_MAC_CARBON
  err = AEInstallEventHandler(kCoreEventClass, kAEQuitApplication,
                              NewAEEventHandlerUPP
			      ((AEEventHandlerProcPtr) do_ae_quit_application),
                              0L, false);
#else
  err = AEInstallEventHandler(kCoreEventClass, kAEQuitApplication,
                              NewAEEventHandlerProc
			      ((AEEventHandlerProcPtr) do_ae_quit_application),
                              0L, false);
#endif
  if (err != noErr)
    abort ();
}

#if USE_CARBON_EVENTS
#ifdef MAC_OSX
void
init_service_handler ()
{
  EventTypeSpec specs[] = {{kEventClassService, kEventServiceGetTypes},
			   {kEventClassService, kEventServiceCopy},
			   {kEventClassService, kEventServicePaste}};
  InstallApplicationEventHandler (NewEventHandlerUPP (mac_handle_service_event),
				  3, specs, NULL, NULL);
}

/*
   MAC_TODO: Check to see if this is called by AEProcessDesc...
 */
OSStatus
mac_handle_service_event (EventHandlerCallRef callRef,
			  EventRef event, void *data)
{
  OSStatus err = noErr;
  switch (GetEventKind (event))
    {
    case kEventServiceGetTypes:
      {
	CFMutableArrayRef copyTypes, pasteTypes;
	CFStringRef type;
	Boolean selection = true;
	/*
	  GetEventParameter(event, kEventParamServicePasteTypes,
	  typeCFMutableArrayRef, NULL,
	  sizeof (CFMutableArrayRef), NULL, &pasteTypes);
	*/
	GetEventParameter(event, kEventParamServiceCopyTypes,
			  typeCFMutableArrayRef, NULL,
			  sizeof (CFMutableArrayRef), NULL, &copyTypes);
	type = CreateTypeStringWithOSType (kScrapFlavorTypeText);
	if (type) {
	  CFArrayAppendValue (copyTypes, type);
	  //CFArrayAppendValue (pasteTypes, type);
	  CFRelease (type);
	}
      }
    case kEventServiceCopy:
      {
	ScrapRef currentScrap, specificScrap;
	char * buf = "";
	Size byteCount = 0;

	GetCurrentScrap (&currentScrap);

	err = GetScrapFlavorSize (currentScrap, kScrapFlavorTypeText, &byteCount);
	if (err == noErr)
	  {
	    void *buffer = xmalloc (byteCount);
	    if (buffer != NULL)
	      {
		GetEventParameter (event, kEventParamScrapRef, typeScrapRef, NULL,
				   sizeof (ScrapRef), NULL, &specificScrap);

		err = GetScrapFlavorData (currentScrap, kScrapFlavorTypeText,
					  &byteCount, buffer);
		if (err == noErr)
		  PutScrapFlavor (specificScrap, kScrapFlavorTypeText,
				  kScrapFlavorMaskNone, byteCount, buffer);
		xfree (buffer);
	      }
	  }
	err = noErr;
      }
    case kEventServicePaste:
      {
	/*
	// Get the current location
        Size     byteCount;
        ScrapRef specificScrap;
        GetEventParameter(event, kEventParamScrapRef, typeScrapRef, NULL,
			  sizeof(ScrapRef), NULL, &specificScrap);
        err = GetScrapFlavorSize(specificScrap, kScrapFlavorTypeText, &byteCount);
        if (err == noErr) {
	  void * buffer = xmalloc(byteCount);
	  if (buffer != NULL ) {
	    err = GetScrapFlavorData(specificScrap, kScrapFlavorTypeText,
				     &byteCount, buffer);
	    if (err == noErr) {
	      // Actually place in the buffer
	      BLOCK_INPUT;
	      // Get the current "selection" string here
	      UNBLOCK_INPUT;
	    }
	  }
	  xfree(buffer);
        }
        */
      }
    }
  return err;
}
#endif

static pascal OSStatus
mac_handle_window_event (next_handler, event, data)
     EventHandlerCallRef next_handler;
     EventRef event;
     void *data;
{
  extern Lisp_Object Qcontrol;

  WindowPtr wp;
  OSStatus result;
  UInt32 attributes;
  XSizeHints *size_hints;

  GetEventParameter (event, kEventParamDirectObject, typeWindowRef,
		     NULL, sizeof (WindowPtr), NULL, &wp);

  switch (GetEventKind (event))
    {
    case kEventWindowUpdate:
      result = CallNextEventHandler (next_handler, event);
      if (result != eventNotHandledErr)
	return result;

      do_window_update (wp);
      break;

    case kEventWindowBoundsChanging:
      result = CallNextEventHandler (next_handler, event);
      if (result != eventNotHandledErr)
	return result;

      GetEventParameter (event, kEventParamAttributes, typeUInt32,
			 NULL, sizeof (UInt32), NULL, &attributes);
      size_hints = FRAME_SIZE_HINTS (mac_window_to_frame (wp));
      if ((attributes & kWindowBoundsChangeUserResize)
	  && ((size_hints->flags & (PResizeInc | PBaseSize | PMinSize))
	      == (PResizeInc | PBaseSize | PMinSize)))
	{
	  Rect bounds;
	  int width, height;

	  GetEventParameter (event, kEventParamCurrentBounds,
			     typeQDRectangle,
			     NULL, sizeof (Rect), NULL, &bounds);
	  width = bounds.right - bounds.left;
	  height = bounds.bottom - bounds.top;

	  if (width < size_hints->min_width)
	    width = size_hints->min_width;
	  else
	    width = size_hints->base_width
	      + (int) ((width - size_hints->base_width)
		       / (float) size_hints->width_inc + .5)
	      * size_hints->width_inc;

	  if (height < size_hints->min_height)
	    height = size_hints->min_height;
	  else
	    height = size_hints->base_height
	      + (int) ((height - size_hints->base_height)
		       / (float) size_hints->height_inc + .5)
	      * size_hints->height_inc;

	  bounds.right = bounds.left + width;
	  bounds.bottom = bounds.top + height;
	  SetEventParameter (event, kEventParamCurrentBounds,
			     typeQDRectangle, sizeof (Rect), &bounds);
	  return noErr;
	}
      break;
    }

  return eventNotHandledErr;
}
#endif	/* USE_CARBON_EVENTS */


OSErr
install_window_handler (window)
     WindowPtr window;
{
  OSErr err = noErr;
#if USE_CARBON_EVENTS
  EventTypeSpec specs[] = {{kEventClassWindow, kEventWindowUpdate},
			   {kEventClassWindow, kEventWindowBoundsChanging}};
  static EventHandlerUPP handle_window_event_UPP = NULL;

  if (handle_window_event_UPP == NULL)
    handle_window_event_UPP = NewEventHandlerUPP (mac_handle_window_event);

  err = InstallWindowEventHandler (window, handle_window_event_UPP,
				   GetEventTypeCount (specs), specs,
				   NULL, NULL);
#endif
#if TARGET_API_MAC_CARBON
  if (mac_do_track_dragUPP == NULL)
    mac_do_track_dragUPP = NewDragTrackingHandlerUPP (mac_do_track_drag);
  if (mac_do_receive_dragUPP == NULL)
    mac_do_receive_dragUPP = NewDragReceiveHandlerUPP (mac_do_receive_drag);

  if (err == noErr)
    err = InstallTrackingHandler (mac_do_track_dragUPP, window, NULL);
  if (err == noErr)
    err = InstallReceiveHandler (mac_do_receive_dragUPP, window, NULL);
#endif
  return err;
}

void
remove_window_handler (window)
     WindowPtr window;
{
#if TARGET_API_MAC_CARBON
  if (mac_do_track_dragUPP)
    RemoveTrackingHandler (mac_do_track_dragUPP, window);
  if (mac_do_receive_dragUPP)
    RemoveReceiveHandler (mac_do_receive_dragUPP, window);
#endif
}

/* Open Application Apple Event */
static pascal OSErr
do_ae_open_application(const AppleEvent *pae, AppleEvent *preply, long prefcon)
{
  return noErr;
}


/* Defined in mac.c.  */
extern int
path_from_vol_dir_name (char *, int, short, long, char *);


/* Called when we receive an AppleEvent with an ID of
   "kAEOpenDocuments".  This routine gets the direct parameter,
   extracts the FSSpecs in it, and puts their names on a list.  */
#pragma options align=mac68k
typedef struct SelectionRange {
  short unused1; // 0 (not used)
  short lineNum; // line to select (<0 to specify range)
  long startRange; // start of selection range (if line < 0)
  long endRange; // end of selection range (if line < 0)
  long unused2; // 0 (not used)
  long theDate; // modification date/time
} SelectionRange;
#pragma options align=reset

static pascal OSErr
do_ae_open_documents(AppleEvent *message, AppleEvent *reply, long refcon)
{
  OSErr err, err2;
  AEDesc the_desc;
  AEKeyword keyword;
  DescType actual_type;
  Size actual_size;
  SelectionRange position;

  err = AEGetParamDesc (message, keyDirectObject, typeAEList, &the_desc);
  if (err != noErr)
    goto descriptor_error_exit;

  err = AEGetParamPtr (message, keyAEPosition, typeChar, &actual_type, &position, sizeof(SelectionRange), &actual_size);
  if (err == noErr)
    drag_and_drop_file_list = Fcons (list3 (make_number (position.lineNum + 1),
					    make_number (position.startRange + 1),
					    make_number (position.endRange + 1)),
				     drag_and_drop_file_list);

  /* Check to see that we got all of the required parameters from the
     event descriptor.  For an 'odoc' event this should just be the
     file list.  */
  err = AEGetAttributePtr(message, keyMissedKeywordAttr, typeWildCard,
			  &actual_type, (Ptr) &keyword,
                          sizeof (keyword), &actual_size);
  /* No error means that we found some unused parameters.
     errAEDescNotFound means that there are no more parameters.  If we
     get an error code other than that, flag it.  */
  if ((err == noErr) || (err != errAEDescNotFound))
    {
      err = errAEEventNotHandled;
      goto error_exit;
    }
  err = noErr;

  /* Got all the parameters we need.  Now, go through the direct
     object list and parse it up.  */
  {
    long num_files_to_open;

    err = AECountItems (&the_desc, &num_files_to_open);
    if (err == noErr)
      {
        int i;

        /* AE file list is one based so just use that for indexing here.  */
        for (i = 1; i <= num_files_to_open; i++)
	  {
	    char unix_path_name[MAXPATHLEN];
#ifdef MAC_OSX
	    FSRef fref;

	    err = AEGetNthPtr (&the_desc, i, typeFSRef, &keyword,
			       &actual_type, &fref, sizeof (FSRef),
			       &actual_size);
	    if (err != noErr || actual_type != typeFSRef)
	      continue;

	    if (FSRefMakePath (&fref, unix_path_name, sizeof (unix_path_name))
		== noErr)
#else
	    FSSpec fs;

	    err = AEGetNthPtr(&the_desc, i, typeFSS, &keyword, &actual_type,
			      (Ptr) &fs, sizeof (fs), &actual_size);
	    if (err != noErr) continue;

	    if (fsspec_to_posix_pathname (&fs, unix_path_name,
					  sizeof (unix_path_name) - 1) == noErr)
#endif
	      /* x-dnd functions expect undecoded filenames.  */
	      drag_and_drop_file_list =
		Fcons (make_unibyte_string (unix_path_name,
					    strlen (unix_path_name)),
		       drag_and_drop_file_list);
	  }
      }
  }

error_exit:
  /* Nuke the coerced file list in any case */
  err2 = AEDisposeDesc(&the_desc);

descriptor_error_exit:
  /* InvalRect(&(gFrontMacWindowP->mWP->portRect)); */
  return err;
}


#if TARGET_API_MAC_CARBON
static pascal OSErr
mac_do_track_drag (DragTrackingMessage message, WindowPtr window,
		   void *handlerRefCon, DragReference theDrag)
{
  static int can_accept;
  short items;
  short index;
  ItemReference theItem;
  FlavorFlags theFlags;
  OSErr result;

  if (GetFrontWindowOfClass (kMovableModalWindowClass, false))
    return dragNotAcceptedErr;

  switch (message)
    {
    case kDragTrackingEnterHandler:
      CountDragItems (theDrag, &items);
      can_accept = 0;
      for (index = 1; index <= items; index++)
	{
	  GetDragItemReferenceNumber (theDrag, index, &theItem);
	  result = GetFlavorFlags (theDrag, theItem, flavorTypeHFS, &theFlags);
	  if (result == noErr)
	    {
	      can_accept = 1;
	      break;
	    }
	}
      break;

    case kDragTrackingEnterWindow:
      if (can_accept)
	{
	  RgnHandle hilite_rgn = NewRgn ();
	  Rect r;
	  struct frame *f = mac_window_to_frame (window);

	  mac_set_backcolor (FRAME_BACKGROUND_PIXEL (f));
	  GetWindowPortBounds (window, &r);
	  OffsetRect (&r, -r.left, -r.top);
	  RectRgn (hilite_rgn, &r);
	  ShowDragHilite (theDrag, hilite_rgn, true);
	  DisposeRgn (hilite_rgn);
	  SetThemeCursor (kThemeCopyArrowCursor);
	}
      break;

    case kDragTrackingInWindow:
      break;

    case kDragTrackingLeaveWindow:
      if (can_accept)
	{
	  struct frame *f = mac_window_to_frame (window);

	  mac_set_backcolor (FRAME_BACKGROUND_PIXEL (f));
	  HideDragHilite (theDrag);
	  SetThemeCursor (kThemeArrowCursor);
	}
      break;

    case kDragTrackingLeaveHandler:
      break;
    }

  return noErr;
}

static pascal OSErr
mac_do_receive_drag (WindowPtr window, void *handlerRefCon,
		     DragReference theDrag)
{
  short items;
  short index;
  FlavorFlags theFlags;
  Point mouse;
  OSErr result;
  ItemReference theItem;
  HFSFlavor data;
  Size size = sizeof (HFSFlavor);

  if (GetFrontWindowOfClass (kMovableModalWindowClass, false))
    return dragNotAcceptedErr;

  drag_and_drop_file_list = Qnil;
  GetDragMouse (theDrag, &mouse, 0L);
  CountDragItems (theDrag, &items);
  for (index = 1; index <= items; index++)
    {
      /* Only handle file references.  */
      GetDragItemReferenceNumber (theDrag, index, &theItem);
      result = GetFlavorFlags (theDrag, theItem, flavorTypeHFS, &theFlags);
      if (result == noErr)
	{
#ifdef MAC_OSX
	  FSRef fref;
#endif
	  char unix_path_name[MAXPATHLEN];

	  GetFlavorData (theDrag, theItem, flavorTypeHFS, &data, &size, 0L);
#ifdef MAC_OSX
	  /* Use Carbon routines, otherwise it converts the file name
	     to /Macintosh HD/..., which is not correct. */
	  FSpMakeFSRef (&data.fileSpec, &fref);
	  if (! FSRefMakePath (&fref, unix_path_name, sizeof (unix_path_name)));
#else
	  if (fsspec_to_posix_pathname (&data.fileSpec, unix_path_name,
					sizeof (unix_path_name) - 1) == noErr)
#endif
	    /* x-dnd functions expect undecoded filenames.  */
            drag_and_drop_file_list =
	      Fcons (make_unibyte_string (unix_path_name,
					  strlen (unix_path_name)),
		     drag_and_drop_file_list);
	}
    }
  /* If there are items in the list, construct an event and post it to
     the queue like an interrupt using kbd_buffer_store_event.  */
  if (!NILP (drag_and_drop_file_list))
    {
      struct input_event event;
      Lisp_Object frame;
      struct frame *f = mac_window_to_frame (window);
      SInt16 modifiers;

      GlobalToLocal (&mouse);
      GetDragModifiers (theDrag, NULL, NULL, &modifiers);

      event.kind = DRAG_N_DROP_EVENT;
      event.code = 0;
      event.modifiers = mac_to_emacs_modifiers (modifiers);
      event.timestamp = TickCount () * (1000 / 60);
      XSETINT (event.x, mouse.h);
      XSETINT (event.y, mouse.v);
      XSETFRAME (frame, f);
      event.frame_or_window = Fcons (frame, drag_and_drop_file_list);
      event.arg = Qnil;
      /* Post to the interrupt queue */
      kbd_buffer_store_event (&event);
      /* MAC_TODO: Mimic behavior of windows by switching contexts to Emacs */
      {
	ProcessSerialNumber psn;
	GetCurrentProcess (&psn);
	SetFrontProcess (&psn);
      }

      return noErr;
    }
  else
    return dragNotAcceptedErr;
}
#endif


/* Print Document Apple Event */
static pascal OSErr
do_ae_print_documents (const AppleEvent *pAE, AppleEvent *reply, long refcon)
{
  return errAEEventNotHandled;
}


static pascal OSErr
do_ae_quit_application (AppleEvent* message, AppleEvent *reply, long refcon)
{
  /* FixMe: Do we need an unwind-protect or something here?  And what
     do we do about unsaved files. Currently just forces quit rather
     than doing recursive callback to get user input.  */

  terminate_flag = true;

  /* Fkill_emacs doesn't return.  We have to return. (TI) */
  return noErr;
}


#if __profile__
void
profiler_exit_proc ()
{
  ProfilerDump ("\pEmacs.prof");
  ProfilerTerm ();
}
#endif

/* These few functions implement Emacs as a normal Mac application
   (almost): set up the heap and the Toolbox, handle necessary
   system events plus a few simple menu events.  They also set up
   Emacs's access to functions defined in the rest of this file.
   Emacs uses function hooks to perform all its terminal I/O.  A
   complete list of these functions appear in termhooks.h.  For what
   they do, read the comments there and see also w32term.c and
   xterm.c.  What's noticeably missing here is the event loop, which
   is normally present in most Mac application.  After performing the
   necessary Mac initializations, main passes off control to
   emacs_main (corresponding to main in emacs.c).  Emacs_main calls
   mac_read_socket (defined further below) to read input.  This is
   where WaitNextEvent is called to process Mac events.  This is also
   where check_alarm in sysdep.c is called to simulate alarm signals.
   This makes the cursor jump back to its correct position after
   briefly jumping to that of the matching parenthesis, print useful
   hints and prompts in the minibuffer after the user stops typing for
   a wait, etc.  */

#ifdef MAC_OS8
#undef main
int
main (void)
{
#if __profile__  /* is the profiler on? */
  if (ProfilerInit(collectDetailed, bestTimeBase, 5000, 200))
    exit(1);
#endif

#if __MWERKS__
  /* set creator and type for files created by MSL */
  _fcreator = 'EMAx';
  _ftype = 'TEXT';
#endif

  do_init_managers ();

  do_get_menus ();

#ifndef USE_LSB_TAG
  do_check_ram_size ();
#endif

  init_emacs_passwd_dir ();

  init_environ ();

  initialize_applescript ();

  init_required_apple_events ();

  {
    char **argv;
    int argc = 0;

    /* set up argv array from STR# resource */
    get_string_list (&argv, ARGV_STRING_LIST_ID);
    while (argv[argc])
      argc++;

    /* free up AppleScript resources on exit */
    atexit (terminate_applescript);

#if __profile__  /* is the profiler on? */
    atexit (profiler_exit_proc);
#endif

    /* 3rd param "envp" never used in emacs_main */
    (void) emacs_main (argc, argv, 0);
  }

  /* Never reached - real exit in Fkill_emacs */
  return 0;
}
#endif

/* Table for translating Mac keycode to X keysym values.  Contributed
   by Sudhir Shenoy.  */
static unsigned char keycode_to_xkeysym_table[] = {
  /*0x00*/ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  /*0x10*/ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  /*0x20*/ 0, 0, 0, 0, 0x0d /*return*/, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

  /*0x30*/ 0x09 /*tab*/, 0 /*0x0020 space*/, 0, 0x08 /*backspace*/,
  /*0x34*/ 0, 0x1b /*escape*/, 0, 0,
  /*0x38*/ 0, 0, 0, 0,
  /*0x3C*/ 0, 0, 0, 0,

  /*0x40*/ 0, 0xae /*kp-.*/, 0, 0xaa /*kp-**/,
  /*0x44*/ 0, 0xab /*kp-+*/, 0, 0x7f /*kp-clear*/,
  /*0x48*/ 0, 0, 0, 0xaf /*kp-/*/,
  /*0x4C*/ 0x8d /*kp-enter*/, 0, 0xad /*kp--*/, 0,

  /*0x50*/ 0, 0xbd /*kp-=*/, 0xb0 /*kp-0*/, 0xb1 /*kp-1*/,
  /*0x54*/ 0xb2 /*kp-2*/, 0xb3 /*kp-3*/, 0xb4 /*kp-4*/, 0xb5 /*kp-5*/,
  /*0x58*/ 0xb6 /*kp-6*/, 0xb7 /*kp-7*/, 0, 0xb8 /*kp-8*/,
  /*0x5C*/ 0xb9 /*kp-9*/, 0, 0, 0,

  /*0x60*/ 0xc2 /*f5*/, 0xc3 /*f6*/, 0xc4 /*f7*/, 0xc0 /*f3*/,
  /*0x64*/ 0xc5 /*f8*/, 0xc6 /*f9*/, 0, 0xc8 /*f11*/,
  /*0x68*/ 0, 0xca /*f13*/, 0, 0xcb /*f14*/,
  /*0x6C*/ 0, 0xc7 /*f10*/, 0, 0xc9 /*f12*/,

  /*0x70*/ 0, 0xcc /*f15*/, 0x9e /*insert (or 0x6a==help)*/, 0x95 /*home*/,
  /*0x74*/ 0x9a /*pgup*/, 0x9f /*delete*/, 0xc1 /*f4*/, 0x9c /*end*/,
  /*0x78*/ 0xbf /*f2*/, 0x9b /*pgdown*/, 0xbe /*f1*/, 0x51 /*left*/,
  /*0x7C*/ 0x53 /*right*/, 0x54 /*down*/, 0x52 /*up*/, 0
};

static int
keycode_to_xkeysym (int keyCode, int *xKeySym)
{
  *xKeySym = keycode_to_xkeysym_table [keyCode & 0x7f];
  return *xKeySym != 0;
}

#if !USE_CARBON_EVENTS
static RgnHandle mouse_region = NULL;

Boolean
mac_wait_next_event (er, sleep_time, dequeue)
     EventRecord *er;
     UInt32 sleep_time;
     Boolean dequeue;
{
  static EventRecord er_buf = {nullEvent};
  UInt32 target_tick, current_tick;
  EventMask event_mask;

  if (mouse_region == NULL)
    mouse_region = NewRgn ();

  event_mask = everyEvent;
  if (NILP (Fboundp (Qmac_ready_for_drag_n_drop)))
    event_mask -= highLevelEventMask;

  current_tick = TickCount ();
  target_tick = current_tick + sleep_time;

  if (er_buf.what == nullEvent)
    while (!WaitNextEvent (event_mask, &er_buf,
			   target_tick - current_tick, mouse_region))
      {
	current_tick = TickCount ();
	if (target_tick <= current_tick)
	  return false;
      }

  *er = er_buf;
  if (dequeue)
    er_buf.what = nullEvent;
  return true;
}
#endif /* not USE_CARBON_EVENTS */

/* Emacs calls this whenever it wants to read an input event from the
   user. */
int
XTread_socket (sd, expected, hold_quit)
     int sd, expected;
     struct input_event *hold_quit;
{
  struct input_event inev;
  int count = 0;
#if USE_CARBON_EVENTS
  EventRef eventRef;
  EventTargetRef toolbox_dispatcher;
#endif
  EventRecord er;
  struct mac_display_info *dpyinfo = &one_mac_display_info;

  if (interrupt_input_blocked)
    {
      interrupt_input_pending = 1;
      return -1;
    }

  interrupt_input_pending = 0;
  BLOCK_INPUT;

  /* So people can tell when we have read the available input.  */
  input_signal_count++;

  /* Don't poll for events to process (specifically updateEvt) if
     window update currently already in progress.  A call to redisplay
     (in do_window_update) can be preempted by another call to
     redisplay, causing blank regions to be left on the screen and the
     cursor to be left at strange places.  */
  if (handling_window_update)
    {
      UNBLOCK_INPUT;
      return 0;
    }

  if (terminate_flag)
    Fkill_emacs (make_number (1));

#if USE_CARBON_EVENTS
  toolbox_dispatcher = GetEventDispatcherTarget ();

  while (!ReceiveNextEvent (0, NULL, kEventDurationNoWait,
			    kEventRemoveFromQueue, &eventRef))
#else /* !USE_CARBON_EVENTS */
  while (mac_wait_next_event (&er, 0, true))
#endif /* !USE_CARBON_EVENTS */
    {
      int do_help = 0;
      struct frame *f;

      /* It is necessary to set this (additional) argument slot of an
	 event to nil because keyboard.c protects incompletely
	 processed event from being garbage collected by placing them
	 in the kbd_buffer_gcpro vector.  */
      EVENT_INIT (inev);
      inev.kind = NO_EVENT;
      inev.arg = Qnil;

#if USE_CARBON_EVENTS
      /* Handle new events */
      if (!mac_convert_event_ref (eventRef, &er))
	switch (GetEventClass (eventRef))
	  {
	  case kEventClassWindow:
	    if (GetEventKind (eventRef) == kEventWindowBoundsChanged)
	      {
		WindowPtr window_ptr;
		GetEventParameter(eventRef, kEventParamDirectObject,
				  typeWindowRef, NULL, sizeof(WindowPtr),
				  NULL, &window_ptr);
		f = mac_window_to_frame (window_ptr);
		if (f && !f->async_iconified)
		  x_real_positions (f, &f->left_pos, &f->top_pos);
		SendEventToEventTarget (eventRef, toolbox_dispatcher);
	      }
	    break;
	  case kEventClassMouse:
	    if (GetEventKind (eventRef) == kEventMouseWheelMoved)
	      {
		SInt32 delta;
		Point point;
		WindowPtr window_ptr = front_emacs_window ();

		if (!IsValidWindowPtr (window_ptr))
		  {
		    SysBeep(1);
		    break;
		  }

		GetEventParameter(eventRef, kEventParamMouseWheelDelta,
				  typeSInt32, NULL, sizeof (SInt32),
				  NULL, &delta);
		GetEventParameter(eventRef, kEventParamMouseLocation,
				  typeQDPoint, NULL, sizeof (Point),
				  NULL, &point);
		inev.kind = WHEEL_EVENT;
		inev.code = 0;
		inev.modifiers = (mac_event_to_emacs_modifiers (eventRef)
				  | ((delta < 0) ? down_modifier
				     : up_modifier));
		SetPortWindowPort (window_ptr);
		GlobalToLocal (&point);
		XSETINT (inev.x, point.h);
		XSETINT (inev.y, point.v);
		XSETFRAME (inev.frame_or_window,
			   mac_window_to_frame (window_ptr));
		inev.timestamp = EventTimeToTicks (GetEventTime (eventRef))*(1000/60);
	      }
	    else
	      SendEventToEventTarget (eventRef, toolbox_dispatcher);

	    break;

	  default:
	    /* Send the event to the appropriate receiver.  */
	    SendEventToEventTarget (eventRef, toolbox_dispatcher);
	  }
      else
#endif /* USE_CARBON_EVENTS */
      switch (er.what)
	{
	case mouseDown:
	case mouseUp:
	  {
	    WindowPtr window_ptr;
	    SInt16 part_code;
	    int tool_bar_p = 0;

#if USE_CARBON_EVENTS
	    /* This is needed to send mouse events like aqua window
	       buttons to the correct handler.  */
	    if (SendEventToEventTarget (eventRef, toolbox_dispatcher)
		!= eventNotHandledErr)
	      break;
#endif

	    if (dpyinfo->grabbed && last_mouse_frame
		&& FRAME_LIVE_P (last_mouse_frame))
	      {
		window_ptr = FRAME_MAC_WINDOW (last_mouse_frame);
		part_code = inContent;
	      }
	    else
	      {
		part_code = FindWindow (er.where, &window_ptr);
		if (tip_window && window_ptr == tip_window)
		  {
		    HideWindow (tip_window);
		    part_code = FindWindow (er.where, &window_ptr);
		  }
	      }

	    if (er.what != mouseDown && part_code != inContent)
	      break;

	    switch (part_code)
	      {
	      case inMenuBar:
		f = mac_window_to_frame (front_emacs_window ());
		saved_menu_event_location = er.where;
		inev.kind = MENU_BAR_ACTIVATE_EVENT;
		XSETFRAME (inev.frame_or_window, f);
		break;

	      case inContent:
		if (window_ptr != front_emacs_window ())
		  SelectWindow (window_ptr);
		else
		  {
		    SInt16 control_part_code;
		    ControlHandle ch;
		    Point mouse_loc = er.where;

		    f = mac_window_to_frame (window_ptr);
		    /* convert to local coordinates of new window */
		    SetPortWindowPort (window_ptr);

		    GlobalToLocal (&mouse_loc);
#if TARGET_API_MAC_CARBON
		    ch = FindControlUnderMouse (mouse_loc, window_ptr,
						&control_part_code);
#else
		    control_part_code = FindControl (mouse_loc, window_ptr,
						     &ch);
#endif

#if USE_CARBON_EVENTS
		    inev.code = mac_get_mouse_btn (eventRef);
		    inev.modifiers = mac_event_to_emacs_modifiers (eventRef);
#else
		    inev.code = mac_get_emulated_btn (er.modifiers);
		    inev.modifiers = mac_to_emacs_modifiers (er.modifiers);
#endif
		    XSETINT (inev.x, mouse_loc.h);
		    XSETINT (inev.y, mouse_loc.v);
		    inev.timestamp = er.when * (1000 / 60);
		    /* ticks to milliseconds */

		    if (dpyinfo->grabbed && tracked_scroll_bar
#if TARGET_API_MAC_CARBON
			|| ch != 0
#else
			|| control_part_code != 0
#endif
			)
		      {
			struct scroll_bar *bar;

			if (dpyinfo->grabbed && tracked_scroll_bar)
			  {
			    bar = tracked_scroll_bar;
			    control_part_code = kControlIndicatorPart;
			  }
			else
			  bar = (struct scroll_bar *) GetControlReference (ch);
			x_scroll_bar_handle_click (bar, control_part_code,
						   &er, &inev);
			if (er.what == mouseDown
			    && control_part_code == kControlIndicatorPart)
			  tracked_scroll_bar = bar;
			else
			  tracked_scroll_bar = NULL;
		      }
		    else
		      {
			Lisp_Object window;
			int x = mouse_loc.h;
			int y = mouse_loc.v;

			window = window_from_coordinates (f, x, y, 0, 0, 0, 1);
			if (EQ (window, f->tool_bar_window))
			  {
			    if (er.what == mouseDown)
			      handle_tool_bar_click (f, x, y, 1, 0);
			    else
			      handle_tool_bar_click (f, x, y, 0,
						     inev.modifiers);
			    tool_bar_p = 1;
			  }
			else
			  {
			    XSETFRAME (inev.frame_or_window, f);
			    inev.kind = MOUSE_CLICK_EVENT;
			  }
		      }

		    if (er.what == mouseDown)
		      {
			dpyinfo->grabbed |= (1 << inev.code);
			last_mouse_frame = f;
			/* Ignore any mouse motion that happened
			   before this event; any subsequent
			   mouse-movement Emacs events should reflect
			   only motion after the ButtonPress.  */
			if (f != 0)
			  f->mouse_moved = 0;

			if (!tool_bar_p)
			  last_tool_bar_item = -1;
		      }
		    else
		      {
			if ((dpyinfo->grabbed & (1 << inev.code)) == 0)
			  /* If a button is released though it was not
			     previously pressed, that would be because
			     of multi-button emulation.  */
			  dpyinfo->grabbed = 0;
			else
			  dpyinfo->grabbed &= ~(1 << inev.code);
		      }

		    switch (er.what)
		      {
		      case mouseDown:
			inev.modifiers |= down_modifier;
			break;
		      case mouseUp:
			inev.modifiers |= up_modifier;
			break;
		      }
		  }
		break;

	      case inDrag:
#if TARGET_API_MAC_CARBON
		DragWindow (window_ptr, er.where, NULL);
#else /* not TARGET_API_MAC_CARBON */
		DragWindow (window_ptr, er.where, &qd.screenBits.bounds);
#endif /* not TARGET_API_MAC_CARBON */
		/* Update the frame parameters.  */
		{
		  struct frame *f = mac_window_to_frame (window_ptr);

		  if (f && !f->async_iconified)
		    x_real_positions (f, &f->left_pos, &f->top_pos);
		}
		break;

	      case inGoAway:
		if (TrackGoAway (window_ptr, er.where))
		  {
		    inev.kind = DELETE_WINDOW_EVENT;
		    XSETFRAME (inev.frame_or_window,
			       mac_window_to_frame (window_ptr));
		  }
		break;

		/* window resize handling added --ben */
	      case inGrow:
		do_grow_window (window_ptr, &er);
		break;

		/* window zoom handling added --ben */
	      case inZoomIn:
	      case inZoomOut:
		if (TrackBox (window_ptr, er.where, part_code))
		  do_zoom_window (window_ptr, part_code);
		break;

	      default:
		break;
	      }
	  }
	  break;

	case updateEvt:
#if USE_CARBON_EVENTS
	  if (SendEventToEventTarget (eventRef, toolbox_dispatcher)
	      != eventNotHandledErr)
	    break;
#else
	  do_window_update ((WindowPtr) er.message);
#endif
	  break;

	case osEvt:
#if USE_CARBON_EVENTS
	  if (SendEventToEventTarget (eventRef, toolbox_dispatcher)
	      != eventNotHandledErr)
	    break;
#endif
	  switch ((er.message >> 24) & 0x000000FF)
	    {
	    case suspendResumeMessage:
	      if ((er.message & resumeFlag) == 1)
		do_app_resume ();
	      else
		do_app_suspend ();
	      break;

	    case mouseMovedMessage:
#if !USE_CARBON_EVENTS
	      SetRectRgn (mouse_region, er.where.h, er.where.v,
			  er.where.h + 1, er.where.v + 1);
#endif
	      previous_help_echo_string = help_echo_string;
	      help_echo_string = help_echo_object = help_echo_window = Qnil;
	      help_echo_pos = -1;

	      do_mouse_moved (er.where, &f);

	      /* If the contents of the global variable
		 help_echo_string has changed, generate a
		 HELP_EVENT.  */
	      if (!NILP (help_echo_string) || !NILP (previous_help_echo_string))
		do_help = 1;
	      break;
	    }
	  break;

	case activateEvt:
	  {
	    WindowPtr window_ptr = (WindowPtr) er.message;

#if USE_CARBON_EVENTS
	    if (SendEventToEventTarget (eventRef, toolbox_dispatcher)
		!= eventNotHandledErr)
	      break;
#endif
	    if (window_ptr == tip_window)
	      {
		HideWindow (tip_window);
		break;
	      }

	    if (!is_emacs_window (window_ptr))
	      break;

	    f = mac_window_to_frame (window_ptr);

	    if ((er.modifiers & activeFlag) != 0)
	      {
		/* A window has been activated */
		Point mouse_loc = er.where;

		x_new_focus_frame (dpyinfo, f);
		activate_scroll_bars (f);

		SetPortWindowPort (window_ptr);
		GlobalToLocal (&mouse_loc);
		/* Window-activated event counts as mouse movement,
		   so update things that depend on mouse position.  */
		note_mouse_movement (mac_window_to_frame (window_ptr),
				     &mouse_loc);
	      }
	    else
	      {
		/* A window has been deactivated */
		dpyinfo->grabbed = 0;

		if (f == dpyinfo->x_focus_frame)
		  {
		    x_new_focus_frame (dpyinfo, 0);
		    deactivate_scroll_bars (f);
		  }


		if (f == dpyinfo->mouse_face_mouse_frame)
		  {
		    /* If we move outside the frame, then we're
		       certainly no longer on any text in the
		       frame.  */
		    clear_mouse_face (dpyinfo);
		    dpyinfo->mouse_face_mouse_frame = 0;
		  }

		/* Generate a nil HELP_EVENT to cancel a help-echo.
		   Do it only if there's something to cancel.
		   Otherwise, the startup message is cleared when the
		   mouse leaves the frame.  */
		if (any_help_event_p)
		  do_help = -1;
	      }
	  }
	  break;

	case keyDown:
	case autoKey:
	  {
	    int keycode = (er.message & keyCodeMask) >> 8;
	    int xkeysym;

#if USE_CARBON_EVENTS && defined (MAC_OSX)
	    /* When using Carbon Events, we need to pass raw keyboard
	       events to the TSM ourselves.  If TSM handles it, it
	       will pass back noErr, otherwise it will pass back
	       "eventNotHandledErr" and we can process it
	       normally.  */
	    if ((!NILP (Vmac_pass_command_to_system)
		 || !(er.modifiers & cmdKey))
		&& (!NILP (Vmac_pass_control_to_system)
		    || !(er.modifiers & controlKey)))
	      if (SendEventToEventTarget (eventRef, toolbox_dispatcher)
		  != eventNotHandledErr)
		break;
#endif

#if TARGET_API_MAC_CARBON
	    if (!IsValidWindowPtr (front_emacs_window ()))
	      {
		SysBeep (1);
		break;
	      }
#endif

	    ObscureCursor ();

	    if (!dpyinfo->mouse_face_hidden && INTEGERP (Vmouse_highlight))
	      {
		clear_mouse_face (dpyinfo);
		dpyinfo->mouse_face_hidden = 1;
	      }

	    if (keycode_to_xkeysym (keycode, &xkeysym))
	      {
		inev.code = 0xff00 | xkeysym;
		inev.kind = NON_ASCII_KEYSTROKE_EVENT;
	      }
	    else
	      {
		if (er.modifiers & (controlKey |
				    (NILP (Vmac_command_key_is_meta) ? optionKey
				     : cmdKey)))
		  {
		    /* This code comes from Keyboard Resource,
		       Appendix C of IM - Text.  This is necessary
		       since shift is ignored in KCHR table
		       translation when option or command is pressed.
		       It also does not translate correctly
		       control-shift chars like C-% so mask off shift
		       here also */
		    int new_modifiers = er.modifiers & 0xe600;
		    /* mask off option and command */
		    int new_keycode = keycode | new_modifiers;
		    Ptr kchr_ptr = (Ptr) GetScriptManagerVariable (smKCHRCache);
		    unsigned long some_state = 0;
		    inev.code = KeyTranslate (kchr_ptr, new_keycode,
					      &some_state) & 0xff;
		  } else if (!NILP(Vmac_option_modifier) && (er.modifiers & optionKey))
            {
                /* When using the option key as an emacs modifier, convert
                   the pressed key code back to one without the Mac option
                   modifier applied. */
                int new_modifiers = er.modifiers & ~optionKey;
                int new_keycode = keycode | new_modifiers;
                Ptr kchr_ptr = (Ptr) GetScriptManagerVariable (smKCHRCache);
                unsigned long some_state = 0;
                inev.code = KeyTranslate (kchr_ptr, new_keycode,
                                          &some_state) & 0xff;
            }
		else
		  inev.code = er.message & charCodeMask;
		inev.kind = ASCII_KEYSTROKE_EVENT;
	      }
	  }

	  /* If variable mac-convert-keyboard-input-to-latin-1 is
	     non-nil, convert non-ASCII characters typed at the Mac
	     keyboard (presumed to be in the Mac Roman encoding) to
	     iso-latin-1 encoding before they are passed to Emacs.
	     This enables the Mac keyboard to be used to enter
	     non-ASCII iso-latin-1 characters directly.  */
	  if (mac_keyboard_text_encoding != kTextEncodingMacRoman
	      && inev.kind == ASCII_KEYSTROKE_EVENT && inev.code >= 128)
	    {
	      static TECObjectRef converter = NULL;
	      OSStatus the_err = noErr;
	      OSStatus convert_status = noErr;

	      if (converter ==  NULL)
		{
		  the_err = TECCreateConverter (&converter,
						kTextEncodingMacRoman,
						mac_keyboard_text_encoding);
		  current_mac_keyboard_text_encoding
		    = mac_keyboard_text_encoding;
		}
	      else if (mac_keyboard_text_encoding
		       != current_mac_keyboard_text_encoding)
		{
		  /* Free the converter for the current encoding
		     before creating a new one.  */
		  TECDisposeConverter (converter);
		  the_err = TECCreateConverter (&converter,
						kTextEncodingMacRoman,
						mac_keyboard_text_encoding);
		  current_mac_keyboard_text_encoding
		    = mac_keyboard_text_encoding;
		}

	      if (the_err == noErr)
		{
		  unsigned char ch = inev.code;
		  ByteCount actual_input_length, actual_output_length;
		  unsigned char outbuf[32];

		  convert_status = TECConvertText (converter, &ch, 1,
						   &actual_input_length,
						   outbuf, 1,
						   &actual_output_length);
		  if (convert_status == noErr
		      && actual_input_length == 1
		      && actual_output_length == 1)
		    inev.code = *outbuf;

		  /* Reset internal states of the converter object.
		     If it fails, create another one. */
		  convert_status = TECFlushText (converter, outbuf,
						 sizeof (outbuf),
						 &actual_output_length);
		  if (convert_status != noErr)
		    {
		      TECDisposeConverter (converter);
		      TECCreateConverter (&converter,
					  kTextEncodingMacRoman,
					  mac_keyboard_text_encoding);
		    }
		}
	    }

#if USE_CARBON_EVENTS
	  inev.modifiers = mac_event_to_emacs_modifiers (eventRef);
#else
	  inev.modifiers = mac_to_emacs_modifiers (er.modifiers);
#endif
	  XSETFRAME (inev.frame_or_window,
		     mac_window_to_frame (front_emacs_window ()));
	  inev.timestamp = er.when * (1000 / 60);  /* ticks to milliseconds */
	  break;

	case kHighLevelEvent:
	  drag_and_drop_file_list = Qnil;

	  AEProcessAppleEvent(&er);

	  /* Build a DRAG_N_DROP_EVENT type event as is done in
	     constuct_drag_n_drop in w32term.c.  */
	  if (!NILP (drag_and_drop_file_list))
	    {
	      struct frame *f = NULL;
	      WindowPtr wp;
	      Lisp_Object frame;

	      wp = front_emacs_window ();

	      if (!wp)
		{
		  struct frame *f = XFRAME (XCAR (Vframe_list));
		  CollapseWindow (FRAME_MAC_WINDOW (f), false);
		  wp = front_emacs_window ();
		}

	      if (wp)
		f = mac_window_to_frame (wp);

	      inev.kind = DRAG_N_DROP_EVENT;
	      inev.code = 0;
	      inev.timestamp = er.when * (1000 / 60);
	      /* ticks to milliseconds */
#if USE_CARBON_EVENTS
	      inev.modifiers = mac_event_to_emacs_modifiers (eventRef);
#else
	      inev.modifiers = mac_to_emacs_modifiers (er.modifiers);
#endif

	      XSETINT (inev.x, 0);
	      XSETINT (inev.y, 0);

	      XSETFRAME (frame, f);
	      inev.frame_or_window = Fcons (frame, drag_and_drop_file_list);

	      /* Regardless of whether Emacs was suspended or in the
		 foreground, ask it to redraw its entire screen.
		 Otherwise parts of the screen can be left in an
		 inconsistent state.  */
	      if (wp)
#if TARGET_API_MAC_CARBON
		{
		  Rect r;

		  GetWindowPortBounds (wp, &r);
		  InvalWindowRect (wp, &r);
		}
#else /* not TARGET_API_MAC_CARBON */
                InvalRect (&(wp->portRect));
#endif /* not TARGET_API_MAC_CARBON */
	    }
	default:
	  break;
	}
#if USE_CARBON_EVENTS
      ReleaseEvent (eventRef);
#endif

      if (inev.kind != NO_EVENT)
	{
	  kbd_buffer_store_event_hold (&inev, hold_quit);
	  count++;
	}

      if (do_help
	  && !(hold_quit && hold_quit->kind != NO_EVENT))
	{
	  Lisp_Object frame;

	  if (f)
	    XSETFRAME (frame, f);
	  else
	    frame = Qnil;

	  if (do_help > 0)
	    {
	      any_help_event_p = 1;
	      gen_help_event (help_echo_string, frame, help_echo_window,
			      help_echo_object, help_echo_pos);
	    }
	  else
	    {
	      help_echo_string = Qnil;
	      gen_help_event (Qnil, frame, Qnil, Qnil, 0);
	    }
	  count++;
	}

    }

  /* If the focus was just given to an autoraising frame,
     raise it now.  */
  /* ??? This ought to be able to handle more than one such frame.  */
  if (pending_autoraise_frame)
    {
      x_raise_frame (pending_autoraise_frame);
      pending_autoraise_frame = 0;
    }

#if !TARGET_API_MAC_CARBON
  check_alarm ();  /* simulate the handling of a SIGALRM */
#endif

  UNBLOCK_INPUT;
  return count;
}


/* Need to override CodeWarrior's input function so no conversion is
   done on newlines Otherwise compiled functions in .elc files will be
   read incorrectly.  Defined in ...:MSL C:MSL
   Common:Source:buffer_io.c.  */
#ifdef __MWERKS__
void
__convert_to_newlines (unsigned char * p, size_t * n)
{
#pragma unused(p,n)
}

void
__convert_from_newlines (unsigned char * p, size_t * n)
{
#pragma unused(p,n)
}
#endif

#ifdef MAC_OS8
void
make_mac_terminal_frame (struct frame *f)
{
  Lisp_Object frame;
  Rect r;

  XSETFRAME (frame, f);

  f->output_method = output_mac;
  f->output_data.mac = (struct mac_output *)
    xmalloc (sizeof (struct mac_output));
  bzero (f->output_data.mac, sizeof (struct mac_output));

  XSETFRAME (FRAME_KBOARD (f)->Vdefault_minibuffer_frame, f);

  FRAME_COLS (f) = 96;
  FRAME_LINES (f) = 4;

  FRAME_CAN_HAVE_SCROLL_BARS (f) = 1;
  FRAME_VERTICAL_SCROLL_BAR_TYPE (f) = vertical_scroll_bar_right;

  FRAME_DESIRED_CURSOR (f) = FILLED_BOX_CURSOR;

  f->output_data.mac->cursor_pixel = 0;
  f->output_data.mac->border_pixel = 0x00ff00;
  f->output_data.mac->mouse_pixel = 0xff00ff;
  f->output_data.mac->cursor_foreground_pixel = 0x0000ff;

#if TARGET_API_MAC_CARBON
  f->output_data.mac->text_cursor = kThemeIBeamCursor;
  f->output_data.mac->nontext_cursor = kThemeArrowCursor;
  f->output_data.mac->modeline_cursor = kThemeArrowCursor;
  f->output_data.mac->hand_cursor = kThemePointingHandCursor;
  f->output_data.mac->hourglass_cursor = kThemeWatchCursor;
  f->output_data.mac->horizontal_drag_cursor = kThemeResizeLeftRightCursor;
#else
  f->output_data.mac->text_cursor = GetCursor (iBeamCursor);
  f->output_data.mac->nontext_cursor = &arrow_cursor;
  f->output_data.mac->modeline_cursor = &arrow_cursor;
  f->output_data.mac->hand_cursor = &arrow_cursor;
  f->output_data.mac->hourglass_cursor = GetCursor (watchCursor);
  f->output_data.mac->horizontal_drag_cursor = &arrow_cursor;
#endif

  FRAME_FONTSET (f) = -1;
  f->output_data.mac->explicit_parent = 0;
  f->left_pos = 8;
  f->top_pos = 32;
  f->border_width = 0;

  f->internal_border_width = 0;

  f->auto_raise = 1;
  f->auto_lower = 1;

  f->new_text_cols = 0;
  f->new_text_lines = 0;

  SetRect (&r, f->left_pos, f->top_pos,
           f->left_pos + FRAME_PIXEL_WIDTH (f),
           f->top_pos + FRAME_PIXEL_HEIGHT (f));

  BLOCK_INPUT;

  if (!(FRAME_MAC_WINDOW (f) =
	NewCWindow (NULL, &r, "\p", true, dBoxProc,
		    (WindowPtr) -1, 1, (long) f->output_data.mac)))
    abort ();
  /* so that update events can find this mac_output struct */
  f->output_data.mac->mFP = f;  /* point back to emacs frame */

  UNBLOCK_INPUT;

  x_make_gc (f);

  /* Need to be initialized for unshow_buffer in window.c.  */
  selected_window = f->selected_window;

  Fmodify_frame_parameters (frame,
                            Fcons (Fcons (Qfont,
                                          build_string ("-*-monaco-medium-r-*--*-90-*-*-*-*-mac-roman")), Qnil));
  Fmodify_frame_parameters (frame,
                            Fcons (Fcons (Qforeground_color,
                                          build_string ("black")), Qnil));
  Fmodify_frame_parameters (frame,
                            Fcons (Fcons (Qbackground_color,
                                          build_string ("white")), Qnil));
}
#endif


/***********************************************************************
			    Initialization
 ***********************************************************************/

int mac_initialized = 0;

void
mac_initialize_display_info ()
{
  struct mac_display_info *dpyinfo = &one_mac_display_info;
  GDHandle main_device_handle;

  bzero (dpyinfo, sizeof (*dpyinfo));

#ifdef MAC_OSX
  dpyinfo->mac_id_name
    = (char *) xmalloc (SCHARS (Vinvocation_name)
			+ SCHARS (Vsystem_name)
			+ 2);
  sprintf (dpyinfo->mac_id_name, "%s@%s",
	   SDATA (Vinvocation_name), SDATA (Vsystem_name));
#else
  dpyinfo->mac_id_name = (char *) xmalloc (strlen ("Mac Display") + 1);
  strcpy (dpyinfo->mac_id_name, "Mac Display");
#endif

  main_device_handle = LMGetMainDevice();

  dpyinfo->reference_count = 0;
  dpyinfo->resx = 75.0;
  dpyinfo->resy = 75.0;
  dpyinfo->color_p = TestDeviceAttribute (main_device_handle, gdDevType);
#ifdef MAC_OSX
  /* HasDepth returns true if it is possible to have a 32 bit display,
     but this may not be what is actually used.  Mac OSX can do better.
     CGMainDisplayID is only available on OSX 10.2 and higher, but the
     header for CGGetActiveDisplayList says that the first display returned
     is the active one, so we use that.  */
  {
    CGDirectDisplayID disp_id[1];
    CGDisplayCount disp_count;
    CGDisplayErr error_code;

    error_code = CGGetActiveDisplayList (1, disp_id, &disp_count);
    if (error_code != 0)
      error ("No display found, CGGetActiveDisplayList error %d", error_code);

    dpyinfo->n_planes = CGDisplayBitsPerPixel (disp_id[0]);
  }
#else
  for (dpyinfo->n_planes = 32; dpyinfo->n_planes > 0; dpyinfo->n_planes >>= 1)
    if (HasDepth (main_device_handle, dpyinfo->n_planes,
		  gdDevType, dpyinfo->color_p))
      break;
#endif
  dpyinfo->height = (**main_device_handle).gdRect.bottom;
  dpyinfo->width = (**main_device_handle).gdRect.right;
  dpyinfo->grabbed = 0;
  dpyinfo->root_window = NULL;
  dpyinfo->image_cache = make_image_cache ();

  dpyinfo->mouse_face_beg_row = dpyinfo->mouse_face_beg_col = -1;
  dpyinfo->mouse_face_end_row = dpyinfo->mouse_face_end_col = -1;
  dpyinfo->mouse_face_face_id = DEFAULT_FACE_ID;
  dpyinfo->mouse_face_window = Qnil;
  dpyinfo->mouse_face_overlay = Qnil;
  dpyinfo->mouse_face_hidden = 0;
}

/* Create an xrdb-style database of resources to supercede registry settings.
   The database is just a concatenation of C strings, finished by an additional
   \0.  The string are submitted to some basic normalization, so

     [ *]option[ *]:[ *]value...

   becomes

     option:value...

   but any whitespace following value is not removed.  */

static char *
mac_make_rdb (xrm_option)
     char *xrm_option;
{
  char *buffer = xmalloc (strlen (xrm_option) + 2);
  char *current = buffer;
  char ch;
  int in_option = 1;
  int before_value = 0;

  do {
    ch = *xrm_option++;

    if (ch == '\n')
      {
        *current++ = '\0';
        in_option = 1;
        before_value = 0;
      }
    else if (ch != ' ')
      {
        *current++ = ch;
        if (in_option && (ch == ':'))
          {
            in_option = 0;
            before_value = 1;
          }
        else if (before_value)
          {
            before_value = 0;
          }
      }
    else if (!(in_option || before_value))
      {
        *current++ = ch;
      }
  } while (ch);

  *current = '\0';

  return buffer;
}

struct mac_display_info *
mac_term_init (display_name, xrm_option, resource_name)
     Lisp_Object display_name;
     char *xrm_option;
     char *resource_name;
{
  struct mac_display_info *dpyinfo;

  BLOCK_INPUT;

  if (!mac_initialized)
    {
      mac_initialize ();
      mac_initialized = 1;
    }

  if (x_display_list)
    error ("Sorry, this version can only handle one display");

  mac_initialize_display_info ();

  dpyinfo = &one_mac_display_info;

  dpyinfo->xrdb = xrm_option ? mac_make_rdb (xrm_option) : NULL;

  /* Put this display on the chain.  */
  dpyinfo->next = x_display_list;
  x_display_list = dpyinfo;

  /* Put it on x_display_name_list.  */
  x_display_name_list = Fcons (Fcons (display_name, Qnil),
                               x_display_name_list);
  dpyinfo->name_list_element = XCAR (x_display_name_list);

  UNBLOCK_INPUT;

  return dpyinfo;
}
/* Get rid of display DPYINFO, assuming all frames are already gone.  */

void
x_delete_display (dpyinfo)
     struct mac_display_info *dpyinfo;
{
  int i;

  /* Discard this display from x_display_name_list and x_display_list.
     We can't use Fdelq because that can quit.  */
  if (! NILP (x_display_name_list)
      && EQ (XCAR (x_display_name_list), dpyinfo->name_list_element))
    x_display_name_list = XCDR (x_display_name_list);
  else
    {
      Lisp_Object tail;

      tail = x_display_name_list;
      while (CONSP (tail) && CONSP (XCDR (tail)))
	{
	  if (EQ (XCAR (XCDR (tail)), dpyinfo->name_list_element))
	    {
	      XSETCDR (tail, XCDR (XCDR (tail)));
	      break;
	    }
	  tail = XCDR (tail);
	}
    }

  if (x_display_list == dpyinfo)
    x_display_list = dpyinfo->next;
  else
    {
      struct x_display_info *tail;

      for (tail = x_display_list; tail; tail = tail->next)
	if (tail->next == dpyinfo)
	  tail->next = tail->next->next;
    }

  /* Free the font names in the font table.  */
  for (i = 0; i < dpyinfo->n_fonts; i++)
    if (dpyinfo->font_table[i].name)
      {
	if (dpyinfo->font_table[i].name != dpyinfo->font_table[i].full_name)
	  xfree (dpyinfo->font_table[i].full_name);
	xfree (dpyinfo->font_table[i].name);
      }

  if (dpyinfo->font_table->font_encoder)
    xfree (dpyinfo->font_table->font_encoder);

  xfree (dpyinfo->font_table);
  xfree (dpyinfo->mac_id_name);

  if (x_display_list == 0)
    {
      mac_clear_font_name_table ();
      bzero (dpyinfo, sizeof (*dpyinfo));
    }
}


#ifdef MAC_OSX
void
mac_check_bundle()
{
  extern int inhibit_window_system;
  extern int noninteractive;
  CFBundleRef appsBundle;
  pid_t child;

  /* No need to test if already -nw*/
  if (inhibit_window_system || noninteractive)
    return;

  appsBundle = CFBundleGetMainBundle();
  if (appsBundle != NULL)
    {
      CFStringRef cfBI = CFSTR("CFBundleIdentifier");
      CFTypeRef res = CFBundleGetValueForInfoDictionaryKey(appsBundle, cfBI);
      /* We found the bundle identifier, now we know we are valid. */
      if (res != NULL)
	{
	  CFRelease(res);
	  return;
	}
    }
  /* MAC_TODO:  Have this start the bundled executable */

  /* For now, prevent the fatal error by bringing it up in the terminal */
  inhibit_window_system = 1;
}

void
MakeMeTheFrontProcess ()
{
  ProcessSerialNumber psn;
  OSErr err;

  err = GetCurrentProcess (&psn);
  if (err == noErr)
    (void) SetFrontProcess (&psn);
}

/***** Code to handle C-g testing  *****/

/* Contains the Mac modifier formed from quit_char */
static mac_quit_char_modifiers = 0;
static mac_quit_char_keycode;
extern int quit_char;

static void
mac_determine_quit_char_modifiers()
{
  /* Todo: Determine modifiers from quit_char. */
  UInt32 qc_modifiers = ctrl_modifier;

  /* Map modifiers */
  mac_quit_char_modifiers = 0;
  if (qc_modifiers & ctrl_modifier)  mac_quit_char_modifiers |= macCtrlKey;
  if (qc_modifiers & shift_modifier) mac_quit_char_modifiers |= macShiftKey;
  if (qc_modifiers & meta_modifier)  mac_quit_char_modifiers |= macMetaKey;
  if (qc_modifiers & alt_modifier)   mac_quit_char_modifiers |= macAltKey;
}

static void
init_quit_char_handler ()
{
  /* TODO: Let this support keys other the 'g' */
  mac_quit_char_keycode = 5;
  /* Look at <architecture/adb_kb_map.h> for details */
  /* http://gemma.apple.com/techpubs/mac/Toolbox/Toolbox-40.html#MARKER-9-184*/

  mac_determine_quit_char_modifiers();
}

static Boolean
quit_char_comp (EventRef inEvent, void *inCompData)
{
  if (GetEventClass(inEvent) != kEventClassKeyboard)
    return false;
  if (GetEventKind(inEvent) != kEventRawKeyDown)
    return false;
  {
    UInt32 keyCode;
    UInt32 keyModifiers;
    GetEventParameter(inEvent, kEventParamKeyCode,
		      typeUInt32, NULL, sizeof(UInt32), NULL, &keyCode);
    if (keyCode != mac_quit_char_keycode)
      return false;
    GetEventParameter(inEvent, kEventParamKeyModifiers,
		      typeUInt32, NULL, sizeof(UInt32), NULL, &keyModifiers);
    if (keyModifiers != mac_quit_char_modifiers)
      return false;
  }
  return true;
}

void
mac_check_for_quit_char ()
{
  EventRef event;
  static EMACS_TIME last_check_time = { 0, 0 };
  static EMACS_TIME one_second = { 1, 0 };
  EMACS_TIME now, t;

  /* If windows are not initialized, return immediately (keep it bouncin').  */
  if (!mac_quit_char_modifiers)
    return;

  /* Don't check if last check is less than a second ago.  */
  EMACS_GET_TIME (now);
  EMACS_SUB_TIME (t, now, last_check_time);
  if (EMACS_TIME_LT (t, one_second))
    return;
  last_check_time = now;

  /* Redetermine modifiers because they are based on lisp variables */
  mac_determine_quit_char_modifiers ();

  /* Fill the queue with events */
  BLOCK_INPUT;
  ReceiveNextEvent (0, NULL, kEventDurationNoWait, false, &event);
  event = FindSpecificEventInQueue (GetMainEventQueue (), quit_char_comp,
				    NULL);
  UNBLOCK_INPUT;
  if (event)
    {
      struct input_event e;

      /* Use an input_event to emulate what the interrupt handler does. */
      EVENT_INIT (e);
      e.kind = ASCII_KEYSTROKE_EVENT;
      e.code = quit_char;
      e.arg = Qnil;
      e.modifiers = NULL;
      e.timestamp = EventTimeToTicks (GetEventTime (event)) * (1000/60);
      XSETFRAME (e.frame_or_window, mac_window_to_frame (front_emacs_window ()));
      /* Remove event from queue to prevent looping. */
      RemoveEventFromQueue (GetMainEventQueue (), event);
      ReleaseEvent (event);
      kbd_buffer_store_event (&e);
    }
}

#endif /* MAC_OSX */

/* Set up use of X before we make the first connection.  */

extern frame_parm_handler mac_frame_parm_handlers[];

static struct redisplay_interface x_redisplay_interface =
{
  mac_frame_parm_handlers,
  x_produce_glyphs,
  x_write_glyphs,
  x_insert_glyphs,
  x_clear_end_of_line,
  x_scroll_run,
  x_after_update_window_line,
  x_update_window_begin,
  x_update_window_end,
  x_cursor_to,
  x_flush,
  0, /* flush_display_optional */
  x_clear_window_mouse_face,
  x_get_glyph_overhangs,
  x_fix_overlapping_area,
  x_draw_fringe_bitmap,
  0, /* define_fringe_bitmap */
  0, /* destroy_fringe_bitmap */
  mac_per_char_metric,
  mac_encode_char,
  mac_compute_glyph_string_overhangs,
  x_draw_glyph_string,
  mac_define_frame_cursor,
  mac_clear_frame_area,
  mac_draw_window_cursor,
  mac_draw_vertical_window_border,
  mac_shift_glyphs_for_insert
};

void
mac_initialize ()
{
  rif = &x_redisplay_interface;

  clear_frame_hook = x_clear_frame;
  ins_del_lines_hook = x_ins_del_lines;
  delete_glyphs_hook = x_delete_glyphs;
  ring_bell_hook = XTring_bell;
  reset_terminal_modes_hook = XTreset_terminal_modes;
  set_terminal_modes_hook = XTset_terminal_modes;
  update_begin_hook = x_update_begin;
  update_end_hook = x_update_end;
  set_terminal_window_hook = XTset_terminal_window;
  read_socket_hook = XTread_socket;
  frame_up_to_date_hook = XTframe_up_to_date;
  mouse_position_hook = XTmouse_position;
  frame_rehighlight_hook = XTframe_rehighlight;
  frame_raise_lower_hook = XTframe_raise_lower;

  set_vertical_scroll_bar_hook = XTset_vertical_scroll_bar;
  condemn_scroll_bars_hook = XTcondemn_scroll_bars;
  redeem_scroll_bar_hook = XTredeem_scroll_bar;
  judge_scroll_bars_hook = XTjudge_scroll_bars;

  scroll_region_ok = 1;         /* we'll scroll partial frames */
  char_ins_del_ok = 1;
  line_ins_del_ok = 1;          /* we'll just blt 'em */
  fast_clear_end_of_line = 1;   /* X does this well */
  memory_below_frame = 0;       /* we don't remember what scrolls
				   off the bottom */
  baud_rate = 19200;

  x_noop_count = 0;
  last_tool_bar_item = -1;
  any_help_event_p = 0;

  /* Try to use interrupt input; if we can't, then start polling.  */
  Fset_input_mode (Qt, Qnil, Qt, Qnil);

#ifdef USE_X_TOOLKIT
  XtToolkitInitialize ();
  Xt_app_con = XtCreateApplicationContext ();
  XtAppSetFallbackResources (Xt_app_con, Xt_default_resources);

  /* Install an asynchronous timer that processes Xt timeout events
     every 0.1s.  This is necessary because some widget sets use
     timeouts internally, for example the LessTif menu bar, or the
     Xaw3d scroll bar.  When Xt timouts aren't processed, these
     widgets don't behave normally.  */
  {
    EMACS_TIME interval;
    EMACS_SET_SECS_USECS (interval, 0, 100000);
    start_atimer (ATIMER_CONTINUOUS, interval, x_process_timeouts, 0);
  }
#endif

#if USE_TOOLKIT_SCROLL_BARS
  xaw3d_arrow_scroll = False;
  xaw3d_pick_top = True;
#endif

#if 0
  /* Note that there is no real way portable across R3/R4 to get the
     original error handler.  */
  XSetErrorHandler (x_error_handler);
  XSetIOErrorHandler (x_io_error_quitter);

  /* Disable Window Change signals;  they are handled by X events.  */
#ifdef SIGWINCH
  signal (SIGWINCH, SIG_DFL);
#endif /* ! defined (SIGWINCH) */

  signal (SIGPIPE, x_connection_signal);
#endif

  BLOCK_INPUT;

#if TARGET_API_MAC_CARBON
  init_required_apple_events ();

#if USE_CARBON_EVENTS && defined (MAC_OSX)
  init_service_handler ();

  init_quit_char_handler ();
#endif

  DisableMenuCommand (NULL, kHICommandQuit);

#ifdef MAC_OSX
  if (!inhibit_window_system)
    MakeMeTheFrontProcess ();
#endif
#endif
  UNBLOCK_INPUT;
}


void
syms_of_macterm ()
{
#if 0
  staticpro (&x_error_message_string);
  x_error_message_string = Qnil;
#endif

  Qmodifier_value = intern ("modifier-value");
  Qalt = intern ("alt");
  Fput (Qalt, Qmodifier_value, make_number (alt_modifier));
  Qhyper = intern ("hyper");
  Fput (Qhyper, Qmodifier_value, make_number (hyper_modifier));
  Qsuper = intern ("super");
  Fput (Qsuper, Qmodifier_value, make_number (super_modifier));

#ifdef MAC_OSX
  Fprovide (intern ("mac-carbon"), Qnil);
#endif

  staticpro (&Qreverse);
  Qreverse = intern ("reverse");

  staticpro (&x_display_name_list);
  x_display_name_list = Qnil;

  staticpro (&last_mouse_scroll_bar);
  last_mouse_scroll_bar = Qnil;

  staticpro (&Qvendor_specific_keysyms);
  Qvendor_specific_keysyms = intern ("vendor-specific-keysyms");

  staticpro (&last_mouse_press_frame);
  last_mouse_press_frame = Qnil;

  Qmac_ready_for_drag_n_drop = intern ("mac-ready-for-drag-n-drop");
  staticpro (&Qmac_ready_for_drag_n_drop);

  Qbig5 = intern ("big5");
  staticpro (&Qbig5);

  Qcn_gb = intern ("cn-gb");
  staticpro (&Qcn_gb);

  Qsjis = intern ("sjis");
  staticpro (&Qsjis);

  Qeuc_kr = intern ("euc-kr");
  staticpro (&Qeuc_kr);

  DEFVAR_BOOL ("x-autoselect-window", &x_autoselect_window_p,
    doc: /* *Non-nil means autoselect window with mouse pointer.  */);
  x_autoselect_window_p = 0;

  DEFVAR_LISP ("x-toolkit-scroll-bars", &Vx_toolkit_scroll_bars,
	       doc: /* If not nil, Emacs uses toolkit scroll bars.  */);
  Vx_toolkit_scroll_bars = Qt;

  DEFVAR_BOOL ("x-use-underline-position-properties",
               &x_use_underline_position_properties,
     doc: /* *Non-nil means make use of UNDERLINE_POSITION font properties.
nil means ignore them.  If you encounter fonts with bogus
UNDERLINE_POSITION font properties, for example 7x13 on XFree prior
to 4.1, set this to nil.  */);
  x_use_underline_position_properties = 0;

  staticpro (&last_mouse_motion_frame);
  last_mouse_motion_frame = Qnil;

  DEFVAR_LISP ("mac-command-key-is-meta", &Vmac_command_key_is_meta,
    doc: /* Non-nil means that the command key is used as the Emacs meta key.
Otherwise the option key is used.  */);
  Vmac_command_key_is_meta = Qt;

  DEFVAR_LISP ("mac-option-modifier", &Vmac_option_modifier,
    doc: /* Modifier to use for the Mac alt/option key.  The value can
be alt, hyper, or super for the respective modifier.  If the value is
nil then the key will act as the normal Mac option modifier.  */);
  Vmac_option_modifier = Qnil;

  DEFVAR_LISP ("mac-reverse-ctrl-meta", &Vmac_reverse_ctrl_meta,
    doc: /* Non-nil means that the control and meta keys are reversed.  This is
useful for non-standard keyboard layouts.  */);
  Vmac_reverse_ctrl_meta = Qnil;

  DEFVAR_LISP ("mac-emulate-three-button-mouse",
	       &Vmac_emulate_three_button_mouse,
    doc: /* t means that when the option-key is held down while pressing the
mouse button, the click will register as mouse-2 and while the
command-key is held down, the click will register as mouse-3.
'reverse means that the the option-key will register for mouse-3
and the command-key will register for mouse-2.  nil means that
no emulation should be done and the modifiers should be placed
on the mouse-1 event. */);
  Vmac_emulate_three_button_mouse = Qnil;

#if USE_CARBON_EVENTS
  DEFVAR_LISP ("mac-wheel-button-is-mouse-2", &Vmac_wheel_button_is_mouse_2,
   doc: /* Non-nil means that the wheel button will be treated as mouse-2 and
the right click will be mouse-3.
Otherwise, the right click will be mouse-2 and the wheel button mouse-3.*/);
  Vmac_wheel_button_is_mouse_2 = Qt;

  DEFVAR_LISP ("mac-pass-command-to-system", &Vmac_pass_command_to_system,
   doc: /* If non-nil, the Mac \"Command\" key is passed on to the Mac
Toolbox for processing before Emacs sees it.  */);
  Vmac_pass_command_to_system = Qt;

  DEFVAR_LISP ("mac-pass-control-to-system", &Vmac_pass_control_to_system,
   doc: /* If non-nil, the Mac \"Control\" key is passed on to the Mac
Toolbox for processing before Emacs sees it.  */);
  Vmac_pass_control_to_system = Qt;

  DEFVAR_LISP ("mac-pass-control-to-system", &Vmac_pass_control_to_system,
   doc: /* If non-nil, the Mac \"Control\" key is passed on to the Mac
Toolbox for processing before Emacs sees it.  */);
  Vmac_pass_control_to_system = Qt;
#endif

  DEFVAR_LISP ("mac-allow-anti-aliasing", &Vmac_use_core_graphics,
   doc: /* If non-nil, allow anti-aliasing.
The text will be rendered using Core Graphics text rendering which
may anti-alias the text.  */);
  Vmac_use_core_graphics = Qnil;

  DEFVAR_INT ("mac-keyboard-text-encoding", &mac_keyboard_text_encoding,
    doc: /* One of the Text Encoding Base constant values defined in the
Basic Text Constants section of Inside Macintosh - Text Encoding
Conversion Manager.  Its value determines the encoding characters
typed at the Mac keyboard (presumed to be in the MacRoman encoding)
will convert into.  E.g., if it is set to kTextEncodingMacRoman (0),
its default value, no conversion takes place.  If it is set to
kTextEncodingISOLatin1 (0x201) or kTextEncodingISOLatin2 (0x202),
characters typed on Mac keyboard are first converted into the
ISO Latin-1 or ISO Latin-2 encoding, respectively before being
passed to Emacs.  Together with Emacs's set-keyboard-coding-system
command, this enables the Mac keyboard to be used to enter non-ASCII
characters directly.  */);
  mac_keyboard_text_encoding = kTextEncodingMacRoman;
}

/* arch-tag: f2259165-4454-4c04-a029-a133c8af7b5b
   (do not change this comment) */
