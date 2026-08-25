# frozen_string_literal: true

require "spec_helper"

# `verbose_error_pages = false` is the production posture, and it has to mean
# what it says. Hiding the exception from the visible text while leaving it in
# an HTML attribute is worse than not hiding it at all: the page looks safe,
# and anyone reading source gets the message anyway.
#
# The mechanism is weft's own rule — a builder kwarg naming a declared param
# renders as an HTML attribute, because params arrive from the wire rather than
# the call site. Recovery values already ride to every depth as overlays, so
# handing them over at the call site adds nothing but the leak.
RSpec.describe "error page disclosure", type: :request do
  def boom_body
    weft_get("/drills/boom").body
  end

  around do |example|
    original = Weft.configuration.verbose_error_pages
    Weft.configuration.verbose_error_pages = false
    example.run
  ensure
    Weft.configuration.verbose_error_pages = original
  end

  it "keeps the exception out of the visible text" do
    expect(boom_body.gsub(/<[^>]*>/, " ")).not_to include("exploded, as requested")
  end

  it "keeps the exception out of the markup entirely, attributes included" do
    expect(boom_body).not_to include("exploded, as requested")
  end

  it "renders no auto-injected recovery value as an HTML attribute" do
    body = boom_body

    expect(body).not_to match(/<[^>]*\bexception=/)
    expect(body).not_to match(/<[^>]*\bstatus_code=/)
    expect(body).not_to match(/<[^>]*\brequest_path=/)
  end

  it "still renders the branded error surface" do
    expect(boom_body).to include("Dropship")
  end

  # The counterweight, and the reason the checks above are not satisfied by the
  # component simply never receiving the value: with verbose on, the message
  # still arrives — as visible text, through the overlays, which is the path
  # that was always doing the real work.
  it "still shows the exception as text when verbose error pages are on" do
    Weft.configuration.verbose_error_pages = true

    expect(boom_body.gsub(/<[^>]*>/, " ")).to include("exploded, as requested")
  end
end
