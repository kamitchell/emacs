/* Display module for Mac OS.
   Copyright (C) 2000, 2001 Free Software Foundation, Inc.

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

#include "macgui.h"
#include "frame.h"

#define RGB_TO_ULONG(r, g, b) (((r) << 16) | ((g) << 8) | (b))

#define RED_FROM_ULONG(color) ((color) >> 16)
#define GREEN_FROM_ULONG(color) (((color) >> 8) & 0xff)
#define BLUE_FROM_ULONG(color) ((color) & 0xff)

/* Do not change `* 0x101' in the following lines to `<< 8'.  If
   changed, image masks in 1-bit depth will not work. */
#define RED16_FROM_ULONG(color) (RED_FROM_ULONG(color) * 0x101)
#define GREEN16_FROM_ULONG(color) (GREEN_FROM_ULONG(color) * 0x101)
#define BLUE16_FROM_ULONG(color) (BLUE_FROM_ULONG(color) * 0x101)

#define BLACK_PIX_DEFAULT(f) RGB_TO_ULONG(0,0,0)
#define WHITE_PIX_DEFAULT(f) RGB_TO_ULONG(255,255,255)

/* A black pixel in a mask bitmap/pixmap means ``draw a source
   pixel''.  A white pixel means ``retain the current pixel''. */
#define PIX_MASK_DRAW(f) BLACK_PIX_DEFAULT(f)
#define PIX_MASK_RETAIN(f) WHITE_PIX_DEFAULT(f)

#define FONT_WIDTH(f)   ((f)->max_bounds.width)
#define FONT_HEIGHT(f)  ((f)->ascent + (f)->descent)
#define FONT_BASE(f)    ((f)->ascent)
#define FONT_DESCENT(f) ((f)->descent)

#define FONT_MAX_WIDTH(f) FONT_WIDTH(f)  /* fix later */

/* Structure recording bitmaps and reference count.
   If REFCOUNT is 0 then this record is free to be reused.  */

struct mac_bitmap_record
{
  char *bitmap_data;
  char *file;
  int refcount;
  int height, width;
};


/* For each display (currently only one on mac), we have a structure that
   records information about it.  */

struct mac_display_info
{
  /* Chain of all mac_display_info structures.  */
  struct mac_display_info *next;

  /* This is a cons cell of the form (NAME . FONT-LIST-CACHE).
     The same cons cell also appears in x_display_name_list.  */
  Lisp_Object name_list_element;

  /* Number of frames that are on this display.  */
  int reference_count;

  /* Dots per inch of the screen.  */
  double resx, resy;

  /* Number of planes on this screen.  */
  int n_planes;

  /* Whether the screen supports color */ 
  int color_p;

#if 0
  /* Number of bits per pixel on this screen.  */
  int n_cbits;
#endif

  /* Dimensions of this screen.  */
  int height, width;
#if 0
  int height_in,width_in;
#endif

  /* Mask of things that cause the mouse to be grabbed.  */
  int grabbed;

#if 0
  /* Emacs bitmap-id of the default icon bitmap for this frame.
     Or -1 if none has been allocated yet.  */
  int icon_bitmap_id;

#endif
  /* The root window of this screen.  */
  Window root_window;

  /* The cursor to use for vertical scroll bars.  */
  Cursor vertical_scroll_bar_cursor;

  /* Resource data base */
  XrmDatabase xrdb;

#if 0
  /* color palette information.  */
  int has_palette;
  struct w32_palette_entry * color_list;
  unsigned num_colors;
  HPALETTE palette;

  /* deferred action flags checked when starting frame update.  */
  int regen_palette;

  /* Keystroke that has been faked by Emacs and will be ignored when
     received; value is reset after key is received.  */
  int faked_key;

#endif

  /* A table of all the fonts we have already loaded.  */
  struct font_info *font_table;

  /* The current capacity of font_table.  */
  int font_table_size;

  /* The number of fonts actually stored in the font table.
     font_table[n] is used and valid iff 0 <= n < n_fonts. 0 <=
     n_fonts <= font_table_size. and font_table[i].name != 0. */
  int n_fonts;

  /* Minimum width over all characters in all fonts in font_table.  */
  int smallest_char_width;

  /* Minimum font height over all fonts in font_table.  */
  int smallest_font_height;

  /* Reusable Graphics Context for drawing a cursor in a non-default face. */
  XGCValues *scratch_cursor_gc;

  /* These variables describe the range of text currently shown in its
     mouse-face, together with the window they apply to. As long as
     the mouse stays within this range, we need not redraw anything on
     its account.  Rows and columns are glyph matrix positions in
     MOUSE_FACE_WINDOW.  */
  int mouse_face_beg_row, mouse_face_beg_col;
  int mouse_face_beg_x, mouse_face_beg_y;
  int mouse_face_end_row, mouse_face_end_col;
  int mouse_face_end_x, mouse_face_end_y;
  int mouse_face_past_end;
  Lisp_Object mouse_face_window;
  int mouse_face_face_id;
  Lisp_Object mouse_face_overlay;

  /* 1 if a mouse motion event came and we didn't handle it right away because
     gc was in progress.  */
  int mouse_face_deferred_gc;

  /* FRAME and X, Y position of mouse when last checked for
     highlighting.  X and Y can be negative or out of range for the frame.  */
  struct frame *mouse_face_mouse_frame;

  int mouse_face_mouse_x, mouse_face_mouse_y;

  /* Nonzero means defer mouse-motion highlighting.  */
  int mouse_face_defer;

  /* Nonzero means that the mouse highlight should not be shown.  */
  int mouse_face_hidden;

  int mouse_face_image_state;

  char *mac_id_name;

  /* Pointer to bitmap records.  */
  struct mac_bitmap_record *bitmaps;

  /* Allocated size of bitmaps field.  */
  int bitmaps_size;

  /* Last used bitmap index.  */
  int bitmaps_last;

  /* The frame (if any) which has the window that has keyboard focus.
     Zero if none.  This is examined by Ffocus_frame in w32fns.c.  Note
     that a mere EnterNotify event can set this; if you need to know the
     last frame specified in a FocusIn or FocusOut event, use
     w32_focus_event_frame.  */
  struct frame *x_focus_frame;

  /* The last frame mentioned in a FocusIn or FocusOut event.  This is
     separate from w32_focus_frame, because whether or not LeaveNotify
     events cause us to lose focus depends on whether or not we have
     received a FocusIn event for it.  */
  struct frame *x_focus_event_frame;

  /* The frame which currently has the visual highlight, and should get
     keyboard input (other sorts of input have the frame encoded in the
     event).  It points to the focus frame's selected window's
     frame.  It differs from w32_focus_frame when we're using a global
     minibuffer.  */
  struct frame *x_highlight_frame;

  /* Cache of images.  */
  struct image_cache *image_cache;
};

#define x_display_info mac_display_info

/* This is a chain of structures for all the X displays currently in use.  */
extern struct x_display_info *x_display_list;

/* This is a chain of structures for all the displays currently in use.  */
extern struct mac_display_info one_mac_display_info;

/* This is a list of cons cells, each of the form (NAME . FONT-LIST-CACHE),
   one for each element of x_display_list and in the same order.
   NAME is the name of the frame.
   FONT-LIST-CACHE records previous values returned by x-list-fonts.  */
extern Lisp_Object x_display_name_list;

/* A flag to control how to display unibyte 8-bit character.  */
extern int unibyte_display_via_language_environment;

extern struct x_display_info *x_display_info_for_display P_ ((Display *));
extern struct x_display_info *x_display_info_for_name P_ ((Lisp_Object));

extern struct mac_display_info *mac_term_init ();

extern Lisp_Object x_list_fonts P_ ((struct frame *, Lisp_Object, int, int));
extern struct font_info *x_get_font_info P_ ((struct frame *f, int));
extern struct font_info *x_load_font P_ ((struct frame *, char *, int));
extern struct font_info *x_query_font P_ ((struct frame *, char *));
extern void x_find_ccl_program P_ ((struct font_info *));

/* When Emacs uses a tty window, tty_display in frame.c points to an
   x_output struct .  */
struct x_output
{
  unsigned long background_pixel;
  unsigned long foreground_pixel;
};

/* The collection of data describing a window on the Mac.  */
struct mac_output {
  /* Placeholder for things accessed through output_data.x.  Must
     appear first.  */
  struct x_output x_compatible;

  /* Menubar "widget" handle.  */
  int menubar_widget;

  Window mWP;			/* pointer to QuickDraw window */
  FRAME_PTR mFP;		/* points back to the frame struct */

#if 0
  int mNumCols;			/* number of characters per column */
  int mNumRows;			/* number of characters per row */
  int mLineHeight;		/* height of one line of text in pixels */
  int mCharWidth;		/* width of one character in pixels */
  int mHomeX;			/* X pixel coordinate of lower left
				   corner of character at (0, 0) */
  int mHomeY;			/* Y pixel coordinate of lower left
				   corner of character at (0, 0) */
  int mHighlight;		/* current highlight state (0 = off). */
  int mTermWinSize;		/* num of lines from top of window
				   affected by ins_del_lines; set by
				   set_terminal_window. */
#endif /* 0 */

#if 0
  /* stuffs used by xfaces.c */
  struct face **param_faces;
  int n_param_faces;
  struct face **computed_faces;
  int n_computed_faces;
  int size_computed_faces;
#endif

  /* Here are the Graphics Contexts for the default font.  */
  GC normal_gc;				/* Normal video */
  GC reverse_gc;			/* Reverse video */
  GC cursor_gc;				/* cursor drawing */

  /* The window used for this frame.
     May be zero while the frame object is being created
     and the window has not yet been created.  */
  Window window_desc;

  /* The window that is the parent of this window.
     Usually this is a window that was made by the window manager,
     but it can be the root window, and it can be explicitly specified
     (see the explicit_parent field, below).  */
  Window parent_desc;

  /* Default ASCII font of this frame. */
  XFontStruct *font;

  /* The baseline offset of the default ASCII font.  */
  int baseline_offset;

  /* If a fontset is specified for this frame instead of font, this
     value contains an ID of the fontset, else -1.  */
  int fontset;

  /* Pixel values used for various purposes.
     border_pixel may be -1 meaning use a gray tile.  */
  unsigned long cursor_pixel;
  unsigned long border_pixel;
  unsigned long mouse_pixel;
  unsigned long cursor_foreground_pixel;

  /* Foreground color for scroll bars.  A value of -1 means use the
     default (black for non-toolkit scroll bars).  */
  unsigned long scroll_bar_foreground_pixel;

  /* Background color for scroll bars.  A value of -1 means use the
     default (background color of the frame for non-toolkit scroll
     bars).  */
  unsigned long scroll_bar_background_pixel;

  /* Descriptor for the cursor in use for this window.  */
  Cursor text_cursor;
  Cursor nontext_cursor;
  Cursor modeline_cursor;
  Cursor hand_cursor;
  Cursor hourglass_cursor;
  Cursor horizontal_drag_cursor;
#if 0
  /* Window whose cursor is hourglass_cursor.  This window is temporarily
     mapped to display a hourglass-cursor.  */
  Window hourglass_window;

  /* Non-zero means hourglass cursor is currently displayed.  */
  unsigned hourglass_p : 1;

  /* Flag to set when the window needs to be completely repainted.  */
  int needs_exposure;

#endif

#if 0
  DWORD dwStyle;
#endif

  /* This is the Emacs structure for the display this frame is on.  */
  /* struct w32_display_info *display_info; */

  /* Nonzero means our parent is another application's window
     and was explicitly specified.  */
  char explicit_parent;

  /* Nonzero means tried already to make this frame visible.  */
  char asked_for_visible;

  /* Nonzero means menubar is currently active.  */
  char menubar_active;

  /* Nonzero means a menu command is being processed.  */
  char menu_command_in_progress;

  /* Nonzero means menubar is about to become active, but should be
     brought up to date first.  */
  volatile char pending_menu_activation;

  /* Relief GCs, colors etc.  */
  struct relief
  {
    XGCValues *gc;
    unsigned long pixel;
    int allocated_p;
  }
  black_relief, white_relief;

  /* The background for which the above relief GCs were set up.
     They are changed only when a different background is involved.  */
  unsigned long relief_background;
};

typedef struct mac_output mac_output;

/* Return the X output data for frame F.  */
#define FRAME_X_OUTPUT(f) ((f)->output_data.mac)

/* Return the Mac window used for displaying data in frame F.  */
#define FRAME_MAC_WINDOW(f) ((f)->output_data.mac->mWP)
#define FRAME_X_WINDOW(f) ((f)->output_data.mac->mWP)

#define FRAME_FOREGROUND_PIXEL(f) ((f)->output_data.x->foreground_pixel)
#define FRAME_BACKGROUND_PIXEL(f) ((f)->output_data.x->background_pixel)

#define FRAME_FONT(f) ((f)->output_data.mac->font)
#define FRAME_FONTSET(f) ((f)->output_data.mac->fontset)

#define FRAME_BASELINE_OFFSET(f) ((f)->output_data.mac->baseline_offset)

/* This gives the w32_display_info structure for the display F is on.  */
#define FRAME_MAC_DISPLAY_INFO(f) (&one_mac_display_info)
#define FRAME_X_DISPLAY_INFO(f) (&one_mac_display_info)

/* This is the `Display *' which frame F is on.  */
#define FRAME_MAC_DISPLAY(f) (0)
#define FRAME_X_DISPLAY(f) (0)

/* This is the 'font_info *' which frame F has.  */
#define FRAME_MAC_FONT_TABLE(f) (FRAME_MAC_DISPLAY_INFO (f)->font_table)

/* Value is the smallest width of any character in any font on frame F.  */

#define FRAME_SMALLEST_CHAR_WIDTH(F) \
     FRAME_MAC_DISPLAY_INFO(F)->smallest_char_width

/* Value is the smallest height of any font on frame F.  */

#define FRAME_SMALLEST_FONT_HEIGHT(F) \
     FRAME_MAC_DISPLAY_INFO(F)->smallest_font_height

/* Return a pointer to the image cache of frame F.  */

#define FRAME_X_IMAGE_CACHE(F) FRAME_MAC_DISPLAY_INFO ((F))->image_cache


/* Mac-specific scroll bar stuff.  */

/* We represent scroll bars as lisp vectors.  This allows us to place
   references to them in windows without worrying about whether we'll
   end up with windows referring to dead scroll bars; the garbage
   collector will free it when its time comes.

   We use struct scroll_bar as a template for accessing fields of the
   vector.  */

struct scroll_bar {

  /* These fields are shared by all vectors.  */
  EMACS_INT size_from_Lisp_Vector_struct;
  struct Lisp_Vector *next_from_Lisp_Vector_struct;

  /* The window we're a scroll bar for.  */
  Lisp_Object window;

  /* The next and previous in the chain of scroll bars in this frame.  */
  Lisp_Object next, prev;

  /* The Mac control handle of this scroll bar.  Since this is a full
     32-bit quantity, we store it split into two 32-bit values.  */
  Lisp_Object control_handle_low, control_handle_high;

  /* The position and size of the scroll bar in pixels, relative to the
     frame.  */
  Lisp_Object top, left, width, height;

  /* The starting and ending positions of the handle, relative to the
     handle area (i.e. zero is the top position, not
     SCROLL_BAR_TOP_BORDER).  If they're equal, that means the handle
     hasn't been drawn yet.

     These are not actually the locations where the beginning and end
     are drawn; in order to keep handles from becoming invisible when
     editing large files, we establish a minimum height by always
     drawing handle bottoms VERTICAL_SCROLL_BAR_MIN_HANDLE pixels below
     where they would be normally; the bottom and top are in a
     different co-ordinate system.  */
  Lisp_Object start, end;

  /* If the scroll bar handle is currently being dragged by the user,
     this is the number of pixels from the top of the handle to the
     place where the user grabbed it.  If the handle isn't currently
     being dragged, this is Qnil.  */
  Lisp_Object dragging;
};

/* The number of elements a vector holding a struct scroll_bar needs.  */
#define SCROLL_BAR_VEC_SIZE					\
  ((sizeof (struct scroll_bar)					\
    - sizeof (EMACS_INT) - sizeof (struct Lisp_Vector *))	\
   / sizeof (Lisp_Object))

/* Turning a lisp vector value into a pointer to a struct scroll_bar.  */
#define XSCROLL_BAR(vec) ((struct scroll_bar *) XVECTOR (vec))


/* Building a 32-bit C integer from two 16-bit lisp integers.  */
#define SCROLL_BAR_PACK(low, high) (XINT (high) << 16 | XINT (low))

/* Setting two lisp integers to the low and high words of a 32-bit C int.  */
#define SCROLL_BAR_UNPACK(low, high, int32) \
  (XSETINT ((low),   (int32)        & 0xffff), \
   XSETINT ((high), ((int32) >> 16) & 0xffff))


/* Extract the Mac control handle of the scroll bar from a struct
   scroll_bar.  */
#define SCROLL_BAR_CONTROL_HANDLE(ptr) \
  ((ControlHandle) SCROLL_BAR_PACK ((ptr)->control_handle_low, \
                                    (ptr)->control_handle_high))

/* Store a Mac control handle in a struct scroll_bar.  */
#define SET_SCROLL_BAR_CONTROL_HANDLE(ptr, id) \
  (SCROLL_BAR_UNPACK ((ptr)->control_handle_low, \
                      (ptr)->control_handle_high, (int) id))

/* Return the inside width of a vertical scroll bar, given the outside
   width.  */
#define VERTICAL_SCROLL_BAR_INSIDE_WIDTH(f,width) \
  ((width) \
   - VERTICAL_SCROLL_BAR_LEFT_BORDER \
   - VERTICAL_SCROLL_BAR_RIGHT_BORDER \
   - VERTICAL_SCROLL_BAR_WIDTH_TRIM * 2)

/* Return the length of the rectangle within which the top of the
   handle must stay.  This isn't equivalent to the inside height,
   because the scroll bar handle has a minimum height.

   This is the real range of motion for the scroll bar, so when we're
   scaling buffer positions to scroll bar positions, we use this, not
   VERTICAL_SCROLL_BAR_INSIDE_HEIGHT.  */
#define VERTICAL_SCROLL_BAR_TOP_RANGE(f,height) \
  (VERTICAL_SCROLL_BAR_INSIDE_HEIGHT (f, height) \
   - VERTICAL_SCROLL_BAR_MIN_HANDLE - UP_AND_DOWN_ARROWS)

/* Return the inside height of vertical scroll bar, given the outside
   height.  See VERTICAL_SCROLL_BAR_TOP_RANGE too.  */
#define VERTICAL_SCROLL_BAR_INSIDE_HEIGHT(f,height) \
  ((height) - VERTICAL_SCROLL_BAR_TOP_BORDER \
   - VERTICAL_SCROLL_BAR_BOTTOM_BORDER)


/* Border widths for scroll bars.

   Scroll bar windows don't have any borders; their border width is
   set to zero, and we redraw borders ourselves.  This makes the code
   a bit cleaner, since we don't have to convert between outside width
   (used when relating to the rest of the screen) and inside width
   (used when sizing and drawing the scroll bar window itself).

   The handle moves up and down/back and forth in a rectangle inset
   from the edges of the scroll bar.  These are widths by which we
   inset the handle boundaries from the scroll bar edges.  */
#define VERTICAL_SCROLL_BAR_LEFT_BORDER (0)
#define VERTICAL_SCROLL_BAR_RIGHT_BORDER (0)
#define VERTICAL_SCROLL_BAR_TOP_BORDER (0)
#define VERTICAL_SCROLL_BAR_BOTTOM_BORDER (0)

/* Minimum lengths for scroll bar handles, in pixels.  */
#define VERTICAL_SCROLL_BAR_MIN_HANDLE (16)

/* Combined length of up and down arrow boxes in scroll bars, in pixels.  */
#define UP_AND_DOWN_ARROWS (32)

/* Trimming off a few pixels from each side prevents
   text from glomming up against the scroll bar */
#define VERTICAL_SCROLL_BAR_WIDTH_TRIM (0)

struct frame;
struct face;
struct image;

Lisp_Object display_x_get_resource P_ ((struct x_display_info *,
					Lisp_Object, Lisp_Object,
					Lisp_Object, Lisp_Object));
struct frame *check_x_frame P_ ((Lisp_Object));
EXFUN (Fx_display_color_p, 1);
EXFUN (Fx_display_grayscale_p, 1);
EXFUN (Fx_display_planes, 1);
extern void x_free_gcs P_ ((struct frame *));

void activate_scroll_bars (FRAME_PTR);
void deactivate_scroll_bars (FRAME_PTR);

/* Defined in macterm.c.  */

extern void x_set_window_size P_ ((struct frame *, int, int, int));
extern void x_make_frame_visible P_ ((struct frame *));
extern void mac_initialize P_ ((void));
extern Pixmap XCreatePixmap P_ ((Display *, WindowPtr, unsigned int,
				 unsigned int, unsigned int));
extern Pixmap XCreatePixmapFromBitmapData P_ ((Display *, WindowPtr, char *,
					       unsigned int, unsigned int,
					       unsigned long, unsigned long,
					       unsigned int));
extern void XFreePixmap P_ ((Display *, Pixmap));
extern void XSetForeground P_ ((Display *, GC, unsigned long));
extern void mac_draw_line_to_pixmap P_ ((Display *, Pixmap, GC, int, int,
					 int, int));

#define FONT_TYPE_FOR_UNIBYTE(font, ch) 0
#define FONT_TYPE_FOR_MULTIBYTE(font, ch) 0

#if TARGET_API_MAC_CARBON
extern CFStringRef cfstring_create_with_utf8_cstring P_ ((const char *));
#endif

/* arch-tag: 6b4ca125-5bef-476d-8ee8-31ed808b7e79
   (do not change this comment) */
