/* Definitions and headers for GTK widgets.
   Copyright (C) 2003
   Free Software Foundation, Inc.

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

#ifndef GTKUTIL_H
#define GTKUTIL_H


#ifdef USE_GTK

#include <gtk/gtk.h>
#include "frame.h"

/* Minimum and maximum values used for GTK scroll bars  */

#define XG_SB_MIN 1
#define XG_SB_MAX 10000000
#define XG_SB_RANGE (XG_SB_MAX-XG_SB_MIN)

/* Key for data that is valid for menus in a frame  */
#define XG_FRAME_DATA "emacs_frame"

/* Key for data that is the last scrollbar value  */
#define XG_LAST_SB_DATA "emacs_last_sb_value"

/* Key for data that menu items hold.  */
#define XG_ITEM_DATA "emacs_menuitem"


/* Button types in menus.  */
enum button_type
{
  BUTTON_TYPE_NONE,
  BUTTON_TYPE_TOGGLE,
  BUTTON_TYPE_RADIO
};

/* This is a list node in a generic list implementation.  */
typedef struct xg_list_node_
{
  struct xg_list_node_ *prev;
  struct xg_list_node_ *next;
} xg_list_node;

/* This structure is the callback data that is shared for menu items.
   We need to keep it separate from the frame structure due to
   detachable menus.  The data in the frame structure is only valid while
   the menu is popped up.  This structure is kept around as long as
   the menu is.  */
typedef struct xg_menu_cb_data_
{
  xg_list_node  ptrs;

  FRAME_PTR     f;
  Lisp_Object   menu_bar_vector;
  int           menu_bar_items_used;
  GCallback     highlight_cb;
  int           ref_count;
} xg_menu_cb_data;

/* This structure holds callback information for each individual menu item.  */
typedef struct xg_menu_item_cb_data_
{
  xg_list_node  ptrs;

  gulong        highlight_id;
  gulong        unhighlight_id;
  gulong        select_id;
  Lisp_Object   help;
  gpointer	call_data;
  xg_menu_cb_data *cl_data;

} xg_menu_item_cb_data;


/* Used to specify menus and dialogs.
   This is an adaption from lwlib for Gtk so we can use more of the same
   code as lwlib in xmenu.c.  */
typedef struct _widget_value
{
  /* name of widget */
  char		*name;
  /* value (meaning depend on widget type) */
  char		*value;
  /* keyboard equivalent. no implications for XtTranslations */
  char		*key;
  /* Help string or nil if none.
     GC finds this string through the frame's menu_bar_vector
     or through menu_items.  */
  Lisp_Object	help;
  /* true if enabled */
  gint	        enabled;
  /* true if selected */
  gint	selected;
  /* The type of a button.  */
  enum button_type button_type;
  /* Contents of the sub-widgets, also selected slot for checkbox */
  struct _widget_value	*contents;
  /* data passed to callback */
  gpointer	call_data;
  /* next one in the list */
  struct _widget_value	*next;

  /* we resource the widget_value structures; this points to the next
     one on the free list if this one has been deallocated.
   */
  struct _widget_value *free_list;
} widget_value;

extern widget_value *malloc_widget_value P_ ((void));
extern void free_widget_value P_ ((widget_value *));

extern char *xg_get_file_name P_ ((FRAME_PTR f,
                                   char *prompt,
                                   char *default_filename,
                                   int mustmatch_p));

extern GtkWidget *xg_create_widget P_ ((char *type,
                                        char *name,
                                        FRAME_PTR f,
                                        widget_value *val,
                                        GCallback select_cb,
                                        GCallback deactivate_cb,
                                        GCallback hightlight_cb));

extern void xg_modify_menubar_widgets P_ ((GtkWidget *menubar,
                                           FRAME_PTR f,
                                           widget_value *val,
                                           int deep_p,
                                           GCallback select_cb,
                                           GCallback deactivate_cb,
                                           GCallback hightlight_cb));

extern int xg_update_frame_menubar P_ ((FRAME_PTR f));

extern void xg_keep_popup P_ ((GtkWidget *menu, GtkWidget *submenu));

extern int xg_get_scroll_id_for_window P_ ((Window wid));

extern void xg_create_scroll_bar P_ ((FRAME_PTR f,
                                      struct scroll_bar *bar,
                                      GCallback scroll_callback,
                                      char *scroll_bar_name));
extern void xg_show_scroll_bar P_ ((int scrollbar_id));
extern void xg_remove_scroll_bar P_ ((FRAME_PTR f, int scrollbar_id));

extern void xg_update_scrollbar_pos P_ ((FRAME_PTR f,
                                         int scrollbar_id,
                                         int top,
                                         int left,
                                         int width,
                                         int height,
                                         int real_left,
                                         int canon_width));

extern void xg_set_toolkit_scroll_bar_thumb P_ ((struct scroll_bar *bar,
                                                 int portion,
                                                 int position,
                                                 int whole));


extern void update_frame_tool_bar P_ ((FRAME_PTR f));
extern void free_frame_tool_bar P_ ((FRAME_PTR f));

extern void xg_resize_widgets P_ ((FRAME_PTR f,
                                   int pixelwidth,
                                   int pixelheight));
extern void xg_frame_cleared P_ ((FRAME_PTR f));
extern void xg_frame_set_char_size P_ ((FRAME_PTR f, int cols, int rows));
extern GtkWidget * xg_win_to_widget P_ ((Window));
extern int xg_create_frame_widgets P_ ((FRAME_PTR f));
extern void x_wm_set_size_hint P_ ((FRAME_PTR f,
                                    long flags,
                                    int user_position));
extern void xg_set_background_color P_ ((FRAME_PTR f, unsigned long bg));

/* Mark all callback data that are Lisp_object:s during GC.  */
extern void xg_mark_data P_ ((void));

/* Initialize GTK specific parts.  */
extern void xg_initialize P_ ((void));

/* Setting scrollbar values invokes the callback.  Use this variable
   to indicate that the callback should do nothing.  */
extern int xg_ignore_gtk_scrollbar;

/* If a detach of a menu is done, this is the menu widget that got
   detached.  Must be set to NULL before popping up popup menus.
   Used with xg_keep_popup to delay deleting popup menus when they
   have been detached.  */
extern GtkWidget *xg_did_tearoff;

#endif /* USE_GTK */
#endif /* GTKUTIL_H */

/* arch-tag: 0757f3dc-00c7-4cee-9e4c-282cf1d34c72
   (do not change this comment) */
