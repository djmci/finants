class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Private app — keep every response out of search indexes.
  after_action -> { response.headers["X-Robots-Tag"] = "noindex, nofollow" }

  private

  # Redirect back to the page the form was submitted from, minus
  # any params that would reopen a drawer (edit/new/transfer).
  def redirect_back_to_page(fallback, anchor: nil, **opts)
    uri = URI.parse(request.referer.to_s)
    if uri&.path.present? && (uri.host.nil? || uri.host == request.host)
      query = Rack::Utils.parse_nested_query(uri.query)
                         .except("edit", "new", "transfer", "edit_txn", "edit_rule", "new_rule")
      uri.query = query.to_query.presence
      target = uri.request_uri
      target += "##{anchor}" if anchor
      redirect_to target, **opts
    else
      redirect_to fallback, **opts
    end
  end
end
