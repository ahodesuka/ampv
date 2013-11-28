
module Ampv
  class ProgressBarWidget < Gtk::DrawingArea
    def initialize(bar_color, head_color, height)
      super()
      modify_bg(Gtk::STATE_NORMAL, Gdk::Color.parse("#000"))
      set_height_request(height)

      signal_connect("expose_event") {
        @cx = window.create_cairo_context
        draw_widget
      }
      @value      = 0
      @bar_color  = bar_color
      @head_color = head_color
    end

    def draw_widget
      @cx.set_source_color(@bar_color)
      @cx.rectangle(0, 0, allocation.width * @value.to_f, allocation.height)
      @cx.fill

      if @value > 0
        @cx.set_source_color(@head_color)
        @cx.rectangle(allocation.width * @value.to_f, 0, 2, allocation.height)
        @cx.fill
      end
    end

    def value=(v)
      @value = v
      queue_draw
    end
  end
end

