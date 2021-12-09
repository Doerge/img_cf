defmodule ImgCf do
  @moduledoc """
    This module provides a Phoenix Component <.img_cf src={Routes...} width=400 > that is a drop-in
    cdn + image resizing service using Cloudflare (CF) Image Resize (IR). The IR feature (paid)
    can resizes images for your on the fly.

    From the Cloudflare website (https://developers.cloudflare.com/images/image-resizing):

      You can resize, adjust quality, and convert images to WebP or AVIF format on demand.
      Cloudflare will automatically cache every derived image at the edge, so you only need
      to store one original image at your origin

    We need to proxy all our traffic through CF, and
    then rewrite the image URLs we want to resize. This package makes it very easy: go to CF
    dashboard and

    1. Domain must be on Cloudflare.
    1. In CF Dashboard: proxy all trafic for your domain
    2. In CF Dashboard: enable the Image Resizing service
    3. In our Phoenix project: use <.img_tag src={Routes.static_path(...)} width=400>

    Usage of the img_tag is almost similar to just using a regular <img ...> tag, except:
      - `src` is always rewritten to the magic IR url.
      - If `width`, or `height` is given, they are used for resizing.
      - A retina version (`srcset` + `2x`), is always attempted, unless turned off.
    
    Cloudflare specific options can be passed into the component with `cf` like so:

    ```
      <.img_cf src=... cf=[retina: false, use_img_dims: false, sharpen: "3"] >
    ```
  """
  use Phoenix.Component

  @env Mix.env()
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
    if @env == :prod or @env == :test do
      # Only use CDN in prod
      run(assigns)
    else
      # Otherwise default to build in, passing all args as-is
      img_render(assigns)
    end
  end

  @doc """
    Rewrite img to on-the-fly CloudFlare Image Resizing via special magic paths:
    https://developers.cloudflare.com/images/image-resizing
  """
  def run(assigns) when is_map(assigns) do
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
      |> img_render()
    else
      img_assigns
      |> Map.put(:src, path)
      |> img_render()
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
    Keyword.put_new(opts, :width, val)
  end

  def maybe_merge_img_dim(opts, :height, %{height: val}) do
    Keyword.put_new(opts, :height, val)
  end

  def maybe_merge_img_dim(opts, _, _), do: opts

  @doc """
  Doubles the :width, and/or :height if present. Otherwise returns `opts` untouched.
  """
  @spec get_opts_2x(opts :: Keyword.t()) :: Keyword.t()
  def get_opts_2x(opts) do
    opts
    |> Keyword.get_and_update(:width, &double/1)
    |> Kernel.elem(1)
    |> Keyword.get_and_update(:height, &double/1)
    |> Kernel.elem(1)
  end

  @spec double(nil | non_neg_integer()) :: {nil | non_neg_integer()} | :pop
  def double(nil), do: :pop
  def double(val), do: {val, val * 2}

  @spec serialize_opts(opts :: Keyword.t()) :: String.t()
  def serialize_opts(opts) do
    opts
    |> Enum.reject(fn {key, _} -> key in @reject_opts end)
    |> Enum.map(fn {key, val} -> Atom.to_string(key) <> "=#{val}" end)
    |> Enum.join(",")
  end
end

