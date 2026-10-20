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

  def money(cents, class: nil)
    tag.span(number_to_currency(cents.to_i / 100.0), class: [ "tabular-nums", binding.local_variable_get(:class) ].compact.join(" "))
  end

  def signed_money(cents, class: nil)
    cls = cents.to_i.negative? ? "text-error" : "text-success"
    tag.span(number_to_currency(cents.to_i / 100.0),
             class: [ "tabular-nums", cls, binding.local_variable_get(:class) ].compact.join(" "))
  end

  # Inline lucide-style icons. All are stroke="currentColor", 24x24 viewBox.
  ICONS = {
    "dashboard"  => '<rect width="7" height="9" x="3" y="3" rx="1"/><rect width="7" height="5" x="14" y="3" rx="1"/><rect width="7" height="9" x="14" y="12" rx="1"/><rect width="7" height="5" x="3" y="16" rx="1"/>',
    "transactions" => '<line x1="8" x2="21" y1="6" y2="6"/><line x1="8" x2="21" y1="12" y2="12"/><line x1="8" x2="21" y1="18" y2="18"/><line x1="3" x2="3.01" y1="6" y2="6"/><line x1="3" x2="3.01" y1="12" y2="12"/><line x1="3" x2="3.01" y1="18" y2="18"/>',
    "accounts"   => '<path d="M21 12V7H5a2 2 0 0 1 0-4h14v4"/><path d="M3 5v14a2 2 0 0 0 2 2h16v-5"/><path d="M18 12a2 2 0 0 0 0 4h4v-4Z"/>',
    "categories" => '<path d="M9 5H2v7l6.29 6.29a1 1 0 0 0 1.42 0l4.58-4.58a1 1 0 0 0 0-1.42Z"/><path d="M6 9.01V9"/><path d="m15 5 6.3 6.3a2.4 2.4 0 0 1 0 3.4L17 19"/><path d="M2 12v6a2 2 0 0 0 2 2h6"/>',
    "transfer"   => '<path d="m21 16-4 4-4-4"/><path d="M17 20V4"/><path d="m3 8 4-4 4 4"/><path d="M7 4v16"/>',
    "plus"       => '<path d="M5 12h14"/><path d="M12 5v14"/>',
    "edit"       => '<path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/>',
    "trash"      => '<path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><line x1="10" x2="10" y1="11" y2="17"/><line x1="14" x2="14" y1="11" y2="17"/>',
    "archive"    => '<rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/>',
    "unarchive"  => '<rect width="20" height="5" x="2" y="3" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h2"/><path d="M20 8v11a2 2 0 0 1-2 2h-2"/><path d="m9 15 3-3 3 3"/><path d="M12 12v9"/>',
    "search"     => '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    "chevron-left" => '<path d="m15 18-6-6 6-6"/>',
    "logout"     => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" x2="9" y1="12" y2="12"/>'
  }.freeze

  def icon(name, class: "size-4")
    tag.svg(
      xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24",
      fill: "none", stroke: "currentColor", "stroke-width": "2",
      "stroke-linecap": "round", "stroke-linejoin": "round",
      class: binding.local_variable_get(:class), "aria-hidden": "true"
    ) { ICONS.fetch(name.to_s).html_safe }
  end
end
