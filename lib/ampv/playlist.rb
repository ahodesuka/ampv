#require "gtk2"

module Ampv
  class Playlist < Gtk::Window

    type_register
    signal_new("play_entry", GLib::Signal::RUN_FIRST, nil, nil, String)
    signal_new("playing_removed", GLib::Signal::RUN_FIRST, nil, nil)
    signal_new("open_file_chooser", GLib::Signal::RUN_FIRST, nil, nil)

    def initialize(x, y, w, h, is_visible)
      buttons = {
        [ Gtk::Stock::OPEN,    "Add to Playlist" ] => lambda { signal_emit("open_file_chooser") },
        [ Gtk::Stock::GO_UP,   "Move Up"         ] => lambda { move_selected_up                 },
        [ Gtk::Stock::GO_DOWN, "Move Down"       ] => lambda { move_selected_down               },
        [ Gtk::Stock::REMOVE,  "Remove Selected" ] => lambda { remove_selected                  },
        [ Gtk::Stock::CLEAR,   "Clear Playlist"  ] => lambda { clear                            }
      }

      super()
      set_title("Playlist - #{PACKAGE}")
      set_default_size(w, h)
      set_skip_taskbar_hint(true)
      move(x, y)

      Gtk::Drag.dest_set(self, Gtk::Drag::DEST_DEFAULT_ALL,
                         [ [ "text/uri-list", 0, 0 ] ],
                         Gdk::DragContext::ACTION_LINK)

      signal_connect("show") { move(@pos[0], @pos[1]) unless @pos.nil? }
      signal_connect("hide") { @pos = window.root_origin }
      signal_connect("delete_event") { hide_on_delete }

      signal_connect("key_press_event") { |_w, e|
        hide_on_delete if e.keyval == Gdk::Keyval::GDK_Escape
      }

      vbox = Gtk::VBox.new(false, 10)
      vbox.border_width = 10
      add(vbox)

      sw = Gtk::ScrolledWindow.new
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)
      vbox.pack_start(sw)

      @model    = Gtk::ListStore.new(String, String)
      @treeview = Gtk::TreeView.new(@model)
      @treeview.enable_search  = false
      @treeview.rubber_banding = true
      @treeview.reorderable = true
      @treeview.selection.mode = Gtk::SELECTION_MULTIPLE

      @treeview.signal_connect("row_activated") { |_w, p, c|
        signal_emit("play_entry", @model.get_iter(p)[0])
      }
      @treeview.signal_connect("key_press_event") { |_w, e|
        remove_selected if e.keyval == Gdk::Keyval::GDK_Delete
      }
      @treeview.signal_connect("button_press_event") { |_w, e|
        @menu.popup(nil, nil, e.button, e.time) if
          e.event_type == Gdk::Event::BUTTON_PRESS and e.button == 3
      }

      ["Name", "Length"].each_with_index { |_x, i|
        renderer = Gtk::CellRendererText.new
        column   = Gtk::TreeViewColumn.new(_x,
                                           renderer,
                                           :text => i)
        if _x == "Name"
          renderer.ellipsize = Pango::ELLIPSIZE_MIDDLE
          column.expand = true
          column.set_cell_data_func(renderer) { |t, c, m, j|
            c.text = File.basename(m.get_value(j, 0)) unless m.get_value(j, 0).nil?
          }
        end

        @treeview.append_column(column)
      }

      sw.add(@treeview)

      hbox = Gtk::HBox.new(true, 5)

      buttons.each { |k, v|
        button = Gtk::Button.new
        button.image = Gtk::Image.new(k[0], Gtk::IconSize::BUTTON)
        button.height_request = 36
        button.set_tooltip_text(k[1])
        button.signal_connect("clicked") { v.call }
        hbox.pack_start(button)
      }

      vbox.pack_start(hbox, false)

      @menu = Gtk::Menu.new
      buttons.each { |k, v|
        item = Gtk::ImageMenuItem.new(k[1])
        item.image = Gtk::Image.new(k[0], Gtk::IconSize::MENU)
        item.signal_connect("activate") { v.call }
        @menu.append(item)
      }
      @menu.show_all

      show_all if is_visible
    end

    def count
      i = 0
      @model.each { i += 1 }
      return i
    end

    def add_file(file)
      contains = false
      @model.each { |m, p, iter|
        if iter[0] == file
          contains = true
          break
        end
      }
      unless contains
        iter = @model.append
        iter[0] = file
      end
    end

    def move_selected_up
      @treeview.selection.selected_rows.each { |path|
        tmp = path.dup
        break if not tmp.prev! or @treeview.selection.selected_rows.include?(tmp)
        @model.move_before(@model.get_iter(path), @model.get_iter(tmp))
      }
    end

    def move_selected_down
      @treeview.selection.selected_rows.reverse.each { |path|
        break if @treeview.selection.selected_rows.include?((tmp = path.dup.next!))
        tmp = @model.get_iter(tmp)
        @model.move_after(@model.get_iter(path), tmp) unless tmp.nil?
      }
    end

    def remove_selected
      to_remove = [ ]
      @treeview.selection.selected_rows.each { |path|
        to_remove.push(@model.get_iter(path))
      }
      to_remove.each { |iter|
        signal_emit("playing_removed") if iter[0] == @playing
        @model.remove(iter)
      }
    end

    def get_next
      @model.each { |m, p, iter|
        return iter.next! ? iter[0] : nil if iter[0] == @playing
      }
      return nil
    end

    def get_prev
      prev = nil
      @model.each { |m, p, iter|
        return prev if iter[0] == @playing
        prev = iter[0]
      }
    end

    def get_entries
      entries = [ ]
      @model.each { |m, p, iter| entries.push(iter[0]) }
      return entries
    end

    def clear
      @model.clear
      signal_emit("playing_removed")
    end

    def set_selected(file)
      @playing = file
      i = 0
      @model.each { |m, p, iter|
        if iter[0] == @playing
          @treeview.set_cursor(Gtk::TreePath.new(i), nil, false)
          break
        end
        i += 1
      }
    end

    def update_length(length)
      @model.each { |m, p, iter|
        if iter[0] == @playing
          iter[1] = Time.at(length).utc.strftime("%H:%M:%S") unless length == 0
          break
        end
      }
    end

  private
    def signal_do_play_entry(file) end
    def signal_do_playing_removed() end
    def signal_do_open_file_chooser() end
  end
end

