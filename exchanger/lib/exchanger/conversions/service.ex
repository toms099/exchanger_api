defmodule Exchanger.Conversions.Service do
  @moduledoc """
  Provides all the common data persistence operations for the `Conversion`
  schema. Also integrates with ExchangesAPI client to perform actual
  conversions against the online service.

  """

  @page_size 5

  import Ecto.Query
  import Ecto.Changeset

  alias Exchanger.Repo
  alias Exchanger.Conversions.Conversion
  alias Exchanger.Conversions.Rates

  @doc """
  Inserts a new conversion into the table; returns errors
  if the validation has failed.

  Returns a tuple with either `{:ok, conversion}` or `{:error, errors}`.
  """
  def create_conversion(%{} = data) do
    changeset = Conversion.changeset(%Conversion{}, data)

    if changeset.valid? do
      %{from: from, to: to, amount: amount} = changeset.changes

      {amount_conv, rate_conv} = convert(from, to, amount)
      conversion = change(changeset, %{amount_conv: amount_conv, rate: rate_conv})

      Repo.insert(conversion)
    else
      {:error, map_errors(changeset.errors)}
    end
  end

  @doc """
  Returns a map with conversions and the record count, according to `params`. The parameters can be:

  %{
    :user_id
    :page    
    :page_size
  }

  Example of returned results:

  ```
  %{
    items: [%Conversion{..}, %Conversion{..}],
    total_count: integer
  }
  ```

  """
  def list_conversions(%{} = params) do
    {page_size, offset} = page_params(params)

    by_user =
      if uid = params[:user_id] do
        user_id = String.to_integer(uid)
        dynamic([c], c.user_id == ^user_id)
      else
        true
      end

    items =
      Conversion
      |> where(^by_user)
      |> offset(^offset)
      |> limit(^page_size)
      |> Repo.all()

    # unfortunately, mnesia doesn't have the count(*) equivalent as in SQL
    total_count = 
      Conversion
      |> select([c], c.id)
      |> where(^by_user)
      |> Repo.all()

    %{items: items, total_count: length(total_count)}
  end

  @doc """
  Stores exchange rates according to the data received
  by the exchanges API.
  """
  def save_rates(%{} = rates) do
    rates = Rates.changeset(%Rates{}, %{base: "EUR", rates: rates})

    Repo.insert(rates)
  end

  @doc """
  Returns the latest Rates result inserted in the database.
  """
  def get_latest_rates() do
    from(r in Rates, limit: 1, order_by: [desc: r.inserted_at])
    |> Repo.one()
  end

  @doc """
  Performs a conversion between currencies.

  Returns the converted value or `nil`.
  """
  def convert(from, to, amount) do
    %{rates: rates} = get_latest_rates()

    [from_rate, to_rate] = [rates[String.to_atom(from)], rates[String.to_atom(to)]]

    rate_conv = to_rate / from_rate
    amount_conv = Float.round(rate_conv * amount, 5)

    {amount_conv, rate_conv}
  end

  defp map_errors(errors) do
    errors
    |> Enum.reduce(%{}, fn {k, {message, _}}, m ->
      Map.put(m, k, message)
    end)
  end

  defp page_params(%{} = params) do
    page_size =
      if p_size = params[:page_size] do
        String.to_integer(p_size)
      else
        @page_size
      end

    offset =
      if p = params[:page] do
        page_size * (String.to_integer(p) - 1)
      else
        0
      end

    {page_size, offset}
  end
end
