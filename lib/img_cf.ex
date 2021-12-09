defmodule ImgCf do
  @moduledoc """
    This module provides a Phoenix Component which provides CDN and on-the-fly image resizing
    through Cloudflares (CF) Image Resize (IR) service.

    Modify your view_helpers function to always import it the img_cf Component:

    lib/myapp_web/myapp_web.ex:

      defp view_helpers do
        ...
        import ImgCf, only: [img_cf: 1]
      end

    and then in config/prod.exs

      config :img_cf, rewrite_urls: true

    From the Cloudflare website (https://developers.cloudflare.com/images/image-resizing):

    > You can resize, adjust quality, and convert images to WebP or AVIF format on demand.
    > Cloudflare will automatically cache every derived image at the edge, so you only need
    > to store one original image at your origin

    We need to proxy all our traffic through CF, and
    then rewrite the image URLs we want to resize. This package makes it very easy:

    1. Domain must be on Cloudflare.
    1. In CF Dashboard: proxy all trafic for your domain
    2. In CF Dashboard: enable the Image Resizing service
    3. In our Phoenix project: use `<.img_tag src={Routes.static_path(...)} width=400>`

    Usage of the `img_cf` tag is almost similar to just using a regular `img` tag, except:

    - `src` is always rewritten to the magic IR url.
    - If `width`, or `height` is given, they are used for resizing.
    - A high definition version (`srcset 2x`), is always attempted, unless turned off.

    #Example

      <.img_cf src={Routes.static_path(...)} />

    Cloudflare specific options can be passed into the component with `cf` like so:

      <.img_cf src={...}
        width="400"
        cf=[retina: false, use_img_dims: false, sharpen: "3"]
      />
  """
  use Phoenix.Component

  @default_opts [
    format: "auto",
    fit: "crop",
    sharpen: "1",
    retina: true,
    use_img_dims: true
  ]
  @reject_opts [:retina, :use_img_dims]

  @doc """
  HTML image tag that provides image resizing on the fly, with no infrastructure setup.

  Either width, height, or srcset is required in `opts`.

  Recommended ways of usage:

  ## Examples

      <.img_cf
        src={Routes.static_path(@conn, "/images/foobar.png")}
        width: 400
        height: 400
        cf: [retina: true, width: 400, height: 400]
      />
  """
  def img_cf(assigns) when is_map(assigns) do
    if Application.get_env(:img_cf, :rewrite_urls, false) do
      # Modify the img assigns to point to Cloudflare
      modify_assigns(assigns)
      |> img_render()
    else
      # This passes all assigns
      img_render(assigns)
    end
  end

  @doc """
    Rewrite img to on-the-fly CloudFlare Image Resizing via special magic paths:
    https://developers.cloudflare.com/images/image-resizing
  """
  @spec modify_assigns(assigns :: map()) :: map()
  def modify_assigns(assigns) when is_map(assigns) do
    # Rewrite img to cdn
    # Options: https://developers.cloudflare.com/images/image-resizing/url-format
    # TODO: https://developers.cloudflare.com/images/image-resizing/responsive-images
    # TODO: Get defaults from config

    # Pop the `src` off the assigns. We need to modify it
    {src, _} = Map.pop!(assigns, :src)

    # Pop the Cloudflare specific options from the `img` tag ones.
    {opts, img_assigns} = Map.pop(assigns, :cf)

    # Merge the default Cloudflare options
    opts =
      if is_nil(opts) do
        @default_opts
      else
        Keyword.merge(opts, @default_opts)
      end

    opts =
      if opts[:use_img_dims] do
        opts
        |> maybe_merge_img_dim(:width, assigns)
        |> maybe_merge_img_dim(:height, assigns)
      else
        opts
      end

    path = "/cdn-cgi/image/" <> serialize_opts(opts) <> src

    if opts[:retina] do
      # For retina we ask the cdn to make a double sized img via the HTML srcset attribute
      opts_str_2x =
        opts
        |> get_opts_2x()
        |> serialize_opts()

      srcset = "/cdn-cgi/image/" <> opts_str_2x <> src <> " 2x"

      img_assigns
      |> Map.put(:src, path)
      |> Map.put(:srcset, srcset)
    else
      img_assigns
      |> Map.put(:src, path)
    end
  end

  def img_render(assigns) do
    ~H"""
      <img
        {assigns}
      />
    """
  end

  def maybe_merge_img_dim(opts, :width, %{width: val}) do
    # The HTML img-attr `width` MUST be an integer, without a unit:
    # https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#attr-width
    case Integer.parse(val) do
      {int, ""} ->
        Keyword.put_new(opts, :width, int)

      _ ->
        throw({:error, "Invalid img attr width."})
    end
  end

  def maybe_merge_img_dim(opts, :height, %{height: val}) do
    # The HTML img-attr height MUST be an integer, without a unit:
    # https://developer.mozilla.org/en-US/docs/Web/HTML/Element/img#attr-width
    case Integer.parse(val) do
      {int, ""} ->
        Keyword.put_new(opts, :height, int)

      _ ->
        throw({:error, "Invalid img attr height."})
    end
  end

  def maybe_merge_img_dim(opts, _, _), do: opts

  @doc """
  Doubles the :width, and/or :height if present. Otherwise returns `opts` untouched.
  """
  @spec get_opts_2x(opts :: Keyword.t()) :: Keyword.t()
  def get_opts_2x(opts) do
    opts
    |> Keyword.get_and_update(:width, &double_or_pop/1)
    |> Kernel.elem(1)
    |> Keyword.get_and_update(:height, &double_or_pop/1)
    |> Kernel.elem(1)
  end

  @spec double_or_pop(nil | non_neg_integer()) :: :pop | {non_neg_integer(), non_neg_integer()}
  def double_or_pop(nil), do: :pop
  def double_or_pop(val), do: {val, val * 2}

  @spec serialize_opts(opts :: Keyword.t()) :: String.t()
  def serialize_opts(opts) do
    opts
    |> Enum.reject(fn {key, _} -> key in @reject_opts end)
    |> Enum.map(fn {key, val} -> Atom.to_string(key) <> "=#{val}" end)
    |> Enum.join(",")
  end
end

