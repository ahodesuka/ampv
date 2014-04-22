module Ampv
  class Playlist < Gtk::Window

    type_register
    signal_new("play_entry", GLib::Signal::RUN_FIRST, nil, nil, String)
    signal_new("playing_removed", GLib::Signal::RUN_FIRST, nil, nil)
    signal_new("open_file_chooser", GLib::Signal::RUN_FIRST, nil, nil)

    WATCHED_PIXBUF = Gtk::Invisible.new.render_icon(Gtk::Stock::OK, Gtk::IconSize::MENU)
    PLAYING_PIXBUF = Gtk::Invisible.new.render_icon(Gtk::Stock::MEDIA_PLAY, Gtk::IconSize::MENU)

    def initialize
      buttons = {
        [ Gtk::Stock::OPEN,    "Add to Playlist" ] => lambda { signal_emit("open_file_chooser") },
        [ Gtk::Stock::GO_UP,   "Move Up"         ] => lambda { move_selected_up                 },
        [ Gtk::Stock::GO_DOWN, "Move Down"       ] => lambda { move_selected_down               },
        [ Gtk::Stock::REMOVE,  "Remove Selected" ] => lambda { remove_selected                  },
        [ Gtk::Stock::CLEAR,   "Clear Playlist"  ] => lambda { clear                            }
      }

      super
      set_title("Playlist - #{PACKAGE}")
      set_default_size(Config["playlist_width"], Config["playlist_height"])
      set_skip_taskbar_hint(true)
      move(Config["playlist_x"], Config["playlist_y"])

      signal_connect("show") { move(@pos[0], @pos[1]) unless @pos.nil? }
      signal_connect("hide") { @pos = window.root_origin }
      signal_connect("delete_event") { hide_on_delete }

      signal_connect("key_press_event") { |_w, e|
        hide_on_delete if e.keyval == Gdk::Keyval::GDK_Escape
      }

      @titles   = Hash.new
      vbox      = Gtk::VBox.new(false, 10)
      sw        = Gtk::ScrolledWindow.new
      @model    = Gtk::ListStore.new(String, String, Gdk::Pixbuf)
      @treeview = Gtk::TreeView.new(@model)
      hbox      = Gtk::HBox.new(true, 5)
      @menu     = Gtk::Menu.new

      vbox.border_width = 10
      sw.set_policy(Gtk::POLICY_AUTOMATIC, Gtk::POLICY_AUTOMATIC)

      @treeview.set_enable_search(false)
      @treeview.set_rubber_banding(true)
      @treeview.set_reorderable(true)
      @treeview.set_tooltip_column(0)
      @treeview.selection.set_mode(Gtk::SELECTION_MULTIPLE)

      @treeview.signal_connect("row_activated") { |w, p, c|
        signal_emit("play_entry", @model.get_iter(p)[0])
      }
      @treeview.signal_connect("key_press_event") { |w, e|
        remove_selected if e.keyval == Gdk::Keyval::GDK_Delete
      }
      @treeview.signal_connect("button_press_event") { |w, e|
        if e.event_type == Gdk::Event::BUTTON_PRESS and e.button == 3
          path = @treeview.get_path(e.x, e.y)[0]
          @treeview.set_cursor(path, nil, false) if path
          @menu.popup(nil, nil, e.button, e.time)
        end
      }

      ["Name", "Length"].each_with_index { |x, i|
        renderer = Gtk::CellRendererText.new
        column   = Gtk::TreeViewColumn.new(x, renderer, :text => i)
        if x == "Name"
          renderer.ellipsize = Pango::ELLIPSIZE_MIDDLE
          column.expand = true
          column.set_cell_data_func(renderer) { |t, c, m, j|
            if @titles[j[0]]
              c.text = @titles[j[0]]
            else
              c.text = File.basename(j[0])
            end
          }
        end

        @treeview.append_column(column)
      }
      @treeview.append_column(Gtk::TreeViewColumn.new("", Gtk::CellRendererPixbuf.new, :pixbuf => 2))

      buttons.each { |k, v|
        button = Gtk::Button.new
        item   = Gtk::ImageMenuItem.new(k[1])

        button.image = Gtk::Image.new(k[0], Gtk::IconSize::BUTTON)
        button.height_request = 36
        button.set_tooltip_text(k[1])
        button.signal_connect("clicked") { v.call }

        item.image = Gtk::Image.new(k[0], Gtk::IconSize::MENU)
        item.signal_connect("activate") { v.call }

        hbox.pack_start(button)
        @menu.append(item)
      }

      sw.add(@treeview)
      vbox.pack_start(sw)
      vbox.pack_start(hbox, false)
      add(vbox)
      @menu.show_all

      show_all if Config["playlist_visible"]
    end

    def count
      i = 0
      @model.each { i += 1 }
      i
    end

    def add_file(file, length = nil, watched = false)
      unless include?(file)
        iter = @model.append
        iter[0] = file
        iter[1] = length if length
        iter[2] = WATCHED_PIXBUF if watched
      end
    end

    def on_playing_watched
      @playing_iter[2] = WATCHED_PIXBUF
      @current_is_watched = true
    end

    def include?(file)
      @model.each { |m, p, iter| return true if iter[0] == file }
      false
    end

    def get_next
      @model.each { |m, p, iter|
        return iter.next! ? iter[0] : nil if iter == @playing_iter
      }
      nil
    end

    def get_prev
      prev = nil
      @model.each { |m, p, iter|
        return prev if iter == @playing_iter
        prev = iter[0]
      }
    end

    def get_entries
      entries = [ ]
      @model.each { |m, p, iter|
        entries << {
          "file"    => iter[0],
          "length"  => iter[1] ? iter[1] : "",
          "watched" => iter[2] == WATCHED_PIXBUF || (iter == @playing_iter && @current_is_watched)
        }
      }
      entries
    end

    def get_files
      files = [ ]
      @model.each { |m, p, iter| files << iter[0] }
      files
    end

    def clear(quiet = false)
      @titles.clear
      @model.clear
      signal_emit("playing_removed") unless quiet or @playing_iter.nil?
      @playing_iter = nil
    end

    def set_selected(file)
      @playing = file
      i = 0
      @model.each { |m, p, iter|
        if iter[0] == @playing
          # reset icon for previous playing entry
          if @playing_iter
            @playing_iter[2] = @current_is_watched ? WATCHED_PIXBUF : nil
          end
          @treeview.set_cursor(Gtk::TreePath.new(i), nil, false)
          @playing_iter = iter
          @current_is_watched = @playing_iter[2] == WATCHED_PIXBUF
          @playing_iter[2] = PLAYING_PIXBUF
          break
        end
        i += 1
      }
    end

    def playing_stopped
      @playing_iter[2] = nil if @playing_iter and @playing_iter[2] == PLAYING_PIXBUF
    end

    def update_length(length)
      return if length == 0
      @playing_iter[1] = Time.at(length).utc.strftime("%H:%M:%S") if @playing_iter
    end

    def update_title(title)
      return unless title
      @titles[@playing_iter[0]] = title
    end

  private
    def move_selected_up
      @treeview.selection.selected_rows.each { |path|
        tmp = path.dup
        # prev!: Returns: true if path has a previous node, and the move was made.
        break unless tmp.prev! or @treeview.selection.selected_rows.include?(tmp)
        @model.move_before(@model.get_iter(path), @model.get_iter(tmp))
      }
    end

    def move_selected_down
      @treeview.selection.selected_rows.reverse.each { |path|
        # next!: Moves the path to point to the next node at the current depth. Returns self
        break if @treeview.selection.selected_rows.include?(tmp = path.dup.next!)
        tmp = @model.get_iter(tmp)
        @model.move_after(@model.get_iter(path), tmp) unless tmp.nil?
      }
    end

    def remove_selected
      to_remove = [ ]
      @treeview.selection.selected_rows.each { |path|
        to_remove << @model.get_iter(path)
      }
      to_remove.each { |iter|
        if iter == @playing_iter
          @playing_iter = nil
          signal_emit("playing_removed")
        end
        @titles.delete(iter[0])
        @model.remove(iter)
      }
    end

    def signal_do_play_entry(file) end
    def signal_do_playing_removed() end
    def signal_do_open_file_chooser() end
  end
end

