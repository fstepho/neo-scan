defmodule Neoscan.Stats do
  @moduledoc false
  import Ecto.Query, warn: false
  alias Neoscan.Stats.Counter
  alias Neoscan.Repo
  alias Neoscan.Blocks
  alias Neoscan.Transactions
  alias Neoscan.Transfers
  alias Neoscan.Addresses
  alias Neoscan.ChainAssets

  require Logger

  @doc """
  Creates an stats.

  ## Examples

      iex> create_stats(%{field: value})
      {:ok, %stats{}}

      iex> create_stats(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def initialize_counter do
    IO.inspect({:initialize_counter_called})

    %{
      :total_blocks => Blocks.count_blocks(),
      :total_transactions => Transactions.count_transactions(),
      :total_addresses => Addresses.count_addresses(),
      :contract_transactions => Transactions.count_transactions(["ContractTransaction"]),
      :claim_transactions => Transactions.count_transactions(["ClaimTransaction"]),
      :invocation_transactions => Transactions.count_transactions(["InvocationTransaction"]),
      :enrollment_transactions => Transactions.count_transactions(["EnrollmentTransaction"]),
      :state_transactions => Transactions.count_transactions(["StateTransaction"]),
      :miner_transactions => Transactions.count_transactions(["MinerTransaction"]),
      :publish_transactions => Transactions.count_transactions(["PublishTransaction"]),
      :issue_transactions => Transactions.count_transactions(["IssueTransaction"]),
      :register_transactions => Transactions.count_transactions(["RegisterTransaction"]),
      :total_transfers => Transfers.count_transfers()
    }
    |> Map.merge(ChainAssets.get_assets_stats())
    |> Counter.changeset()
    |> Repo.insert!()
    |> IO.inspect()
  end

  @doc """
  Updates an stats.

  ## Examples

      iex> update_stats(stats, %{field: new_value})
      {:ok, %stats{}}

      iex> update_stats(stats, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_counter(%Counter{} = counter, attrs) do
    counter
    |> Counter.update_changeset(attrs)
    |> Repo.update!()
  end

  def get_counter do
    IO.inspect({:get_counter_called})

    Repo.all(Counter)
    |> List.first()
    |> create_if_doesnt_exists()
  end

  def create_if_doesnt_exists(nil) do
    initialize_counter()
  end

  def create_if_doesnt_exists(counter) do
    counter
  end

  def add_block_to_table do
    counter = get_counter()
    attrs = %{:total_blocks => Map.get(counter, :total_blocks) + 1}
    update_counter(counter, attrs)
  end

  def set_blocks(amount) do
    counter = get_counter()
    attrs = %{:total_blocks => amount}
    update_counter(counter, attrs)
  end

  def add_transaction_to_table(transaction) do
    counter = get_counter()
    attrs = get_attrs_for_type(counter, transaction)

    attrs =
      case Map.get(transaction, :asset_moved) do
        nil ->
          attrs

        asset ->
          {_, new_map} =
            Map.get(counter, :assets_transactions)
            |> Map.get_and_update(asset, fn n ->
              case n do
                nil ->
                  {n, 1}

                n ->
                  {n, n + 1}
              end
            end)

          Map.put(attrs, :assets_transactions, new_map)
      end

    update_counter(counter, attrs)
  end

  def add_transfer_to_table(transfer) do
    counter = get_counter()
    attrs = %{:total_transfers => Map.get(counter, :total_transfers) + 1}

    {_, new_map} =
      Map.get(counter, :assets_transactions)
      |> Map.get_and_update(transfer.contract, fn n ->
        case n do
          nil ->
            {n, 1}

          n ->
            {n, n + 1}
        end
      end)

    attrs = Map.put(attrs, :assets_transactions, new_map)

    update_counter(counter, attrs)
  end

  def get_attrs_for_type(%{total_transactions: t, contract_transactions: c}, %{
        type: "ContractTransaction"
      }) do
    %{total_transactions: t + 1, contract_transactions: c + 1}
  end

  def get_attrs_for_type(%{total_transactions: t, invocation_transactions: c}, %{
        type: "InvocationTransaction"
      }) do
    %{total_transactions: t + 1, invocation_transactions: c + 1}
  end

  def get_attrs_for_type(%{total_transactions: t, enrollment_transactions: c}, %{
        type: "EnrollmentTransaction"
      }) do
    %{total_transactions: t + 1, enrollment_transactions: c + 1}
  end

  def get_attrs_for_type(%{total_transactions: t, state_transactions: c}, %{
        type: "StateTransaction"
      }) do
    %{total_transactions: t + 1, state_transactions: c + 1}
  end

  def get_attrs_for_type(%{total_transactions: t, claim_transactions: c}, %{
        type: "ClaimTransaction"
      }) do
    %{total_transactions: t + 1, claim_transactions: c + 1}
  end

  def get_attrs_for_type(%{total_transactions: t, publish_transactions: c}, %{
        type: "PublishTransaction"
      }) do
    %{total_transactions: t + 1, publish_transactions: c + 1}
  end

  def get_attrs_for_type(%{total_transactions: t, register_transactions: c}, %{
        type: "RegisterTransaction"
      }) do
    %{total_transactions: t + 1, register_transactions: c + 1}
  end

  def get_attrs_for_type(%{total_transactions: t, issue_transactions: c}, %{
        type: "IssueTransaction"
      }) do
    %{total_transactions: t + 1, issue_transactions: c + 1}
  end

  def get_attrs_for_type(%{miner_transactions: c}, %{type: "MinerTransaction"}) do
    %{miner_transactions: c + 1}
  end

  def add_address_to_table do
    %{:total_addresses => addresses} = counter = get_counter()
    update_counter(counter, %{:total_addresses => addresses + 1})
  end

  def count_transactions do
    counter = get_counter()

    [
      %{
        "ContractTransaction" => Map.get(counter, :contract_transactions),
        "ClaimTransaction" => Map.get(counter, :claim_transactions),
        "InvocationTransaction" => Map.get(counter, :invocation_transactions),
        "MinerTransaction" => Map.get(counter, :miner_transactions),
        "PublishTransaction" => Map.get(counter, :publish_transactions),
        "IssueTransaction" => Map.get(counter, :issue_transactions),
        "RegisterTransaction" => Map.get(counter, :register_transactions),
        "EnrollmentTransaction" => Map.get(counter, :enrollment_transactions),
        "StateTransaction" => Map.get(counter, :state_transactions)
      },
      Map.get(counter, :total_transactions),
      Map.get(counter, :total_transfers)
    ]
  end

  def count_addresses do
    get_counter()
    |> Map.get(:total_addresses)
  end

  def count_blocks do
    get_counter()
    |> Map.get(:total_blocks)
  end

  def count_transfers do
    get_counter()
    |> Map.get(:total_transfers)
  end

  def count_transactions_for_asset(txid) do
    get_counter()
    |> Map.get(:assets_transactions)
    |> Map.get(txid)
    |> check_if_nil
  end

  def check_if_nil(nil) do
    0
  end

  def check_if_nil(result) do
    result
  end
end
