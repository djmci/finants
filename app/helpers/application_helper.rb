module ApplicationHelper
  # Red Ant wordmark: "Ant" in brand red.
  def finants_wordmark(class: "font-bold text-lg")
    tag.span(class: binding.local_variable_get(:class)) do
      safe_join([ "Fin", tag.span("Ant", class: "text-[#FF2A00]"), "s" ])
    end
  end

  def ant_icon(size: 24, class: nil)
    render "shared/ant_icon", size: size, class: binding.local_variable_get(:class)
  end
end
