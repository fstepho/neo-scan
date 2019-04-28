defmodule NeoscanSync.Syncer do
  alias Ecto.ConstraintError

  alias NeoscanSync.Converter
  alias Neoscan.Repo
  alias Neoscan.Blocks
  alias NeoscanSync.TokenSyncer

  use GenServer

  require Logger

  @parallelism 16
  @update_interval 1_000
  @block_chunk_size 500

  def start_link do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    missing_block_indexes = Blocks.get_missing_block_indexes()
    Logger.warn("found #{Enum.count(missing_block_indexes)} missing blocks")
    Process.send_after(self(), :sync, 0)
    {:ok, missing_block_indexes}
  end

  def get_available_block_index_range do
    max_index_in_db = Blocks.get_max_index() + 1
    max_index_available = NeoscanNode.get_last_block_index()

    if max_index_in_db > max_index_available do
      []
    else
      Enum.to_list(max_index_in_db..max_index_available)
    end
  end

  @impl true
  def handle_info(:sync, missing_block_indexes) do
    Process.send_after(self(), :sync, @update_interval)
    available_block_index_range = get_available_block_index_range()
    indexes = missing_block_indexes ++ Enum.take(available_block_index_range, @block_chunk_size)
    sync_indexes(indexes)
    {:noreply, []}
  end

  def download_block(index) do
    block_raw = NeoscanNode.get_block_with_transfers(index)
    ^index = block_raw.index
    Converter.convert_block(block_raw)
  catch
    error, reason ->
      Logger.error("error while downloading block #{inspect({index, error, reason})}")
      Logger.error("#{inspect(__STACKTRACE__)}")
      download_block(index)
  end

  def insert_block(block) do
    Enum.each(block.transactions, fn %{transfers: transfers} ->
      Enum.each(transfers, fn %{contract: contract} ->
        TokenSyncer.retrieve_contract(block.index, contract)
      end)
    end)

    Repo.transaction(
      fn ->
        Repo.insert!(block, timeout: :infinity, returning: false)
      end,
      timeout: :infinity
    )

    :ok
  catch
    :error, %ConstraintError{constraint: "blocks_pkey"} ->
      Logger.error("block already #{block.index} in the database")

    error, reason ->
      Logger.error("error while loading block #{inspect({block.index, error, reason})}")
      Logger.error("#{inspect(__STACKTRACE__)}")
      insert_block(block)
  end

  def sync_indexes(indexes) do
    concurrency = System.schedulers_online() * @parallelism

    indexes
    |> Task.async_stream(
      fn n ->
        now = Time.utc_now()
        block = download_block(n)
        Monitor.incr(:download_blocks_time, Time.diff(Time.utc_now(), now, :microseconds))
        Monitor.incr(:download_blocks_count, 1)
        block
      end,
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Task.async_stream(
      fn {:ok, block} ->
        now = Time.utc_now()
        insert_block(block)
        Monitor.incr(:insert_blocks_time, Time.diff(Time.utc_now(), now, :microseconds))
        Monitor.incr(:insert_blocks_count, 1)
        Monitor.incr(:insert_transactions_count, block.tx_count)
      end,
      max_concurrency: System.schedulers_online(),
      timeout: :infinity
    )
    |> Stream.run()
  end
end
