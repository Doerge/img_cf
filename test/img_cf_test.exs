defmodule ImgCfTest do
  use ExUnit.Case
  doctest ImgCf

  # import Phoenix.HTML

  test "greets the world" do
    dom =
      ImgCf.img_cf(%{src: "/images/foobar.png", width: 400})
      |> to_html()

    # Assert the HTML tag field is set
    assert dom =~ ~s(width="400")

    # Assert the Cloudflare params are set
    assert dom =~ ~s(width=400)
    # Assert the Cloudflare params are set for retina srcset
    assert dom =~ ~s(width=800)
    IO.puts(dom)
  end

  def to_html(template) do
    template
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end

