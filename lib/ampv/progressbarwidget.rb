module Ampv
  class ProgressBarWidget < Gtk::DrawingArea

    def initialize
      super
      modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse("#000"))
      set_size_request(-1, Config["progress_bar_height"])

      @value      = 0
      @bar_color  = Config["bar_color"]
      @head_color = Config["head_color"]

      signal_connect("expose_event") {
        @cx = window.create_cairo_context
        @cx.set_source_color(@bar_color)
        @cx.rectangle(0, 0, (allocation.width * @value.to_f).round, allocation.height)
        @cx.fill

        if @value > 0
          @cx.set_source_color(@head_color)
          @cx.rectangle((allocation.width * @value.to_f).round, 0, 2, allocation.height)
          @cx.fill
        end
      }
    end

    def value=(v)
      @value = v
      queue_draw
    end
  end
end

