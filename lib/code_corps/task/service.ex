defmodule CodeCorps.Task.Service do
  @moduledoc """
  Handles special CRUD operations for `CodeCorps.Task`.
  """

  alias CodeCorps.{GitHub, GithubIssue, Repo, Task}
  alias GitHub.Event.Issues.IssueLinker
  alias Ecto.{Changeset, Multi}

  require Logger

  @doc ~S"""
  Performs all actions involved in creating a task on a project
  """
  @spec create(map) :: {:ok, Task.t} | {:error, Changeset.t} | {:error, :github}
  def create(%{} = attributes) do
    Multi.new
    |> Multi.insert(:task, %Task{} |> Task.create_changeset(attributes))
    |> Multi.run(:github, (fn %{task: %Task{} = task} -> task |> create_on_github() end))
    |> Repo.transaction
    |> marshall_result()
  end

  @spec update(Task.t, map) :: {:ok, Task.t} | {:error, Changeset.t} | {:error, :github}
  def update(%Task{} = task, %{} = attributes) do
    Multi.new
    |> Multi.update(:task, task |> Task.update_changeset(attributes))
    |> Multi.run(:github, (fn %{task: %Task{} = task} -> task |> update_on_github() end))
    |> Repo.transaction
    |> marshall_result()
  end

  @spec marshall_result(tuple) :: {:ok, Task.t} | {:error, Changeset.t} | {:error, :github}
  defp marshall_result({:ok, %{github: %Task{} = task}}), do: {:ok, task}
  defp marshall_result({:error, :task, %Changeset{} = changeset, _steps}), do: {:error, changeset}
  defp marshall_result({:error, :github, result, _steps}) do
    Logger.info "An error occurred when creating/updating the task with the GitHub API"
    Logger.info "#{inspect result}"
    {:error, :github}
  end

  @preloads [:github_issue, [github_repo: :github_app_installation], :user]

  @spec create_on_github(Task.t) :: {:ok, Task.t} :: {:error, GitHub.api_error_struct}
  defp create_on_github(%Task{github_repo_id: nil} = task), do: {:ok, task}
  defp create_on_github(%Task{github_repo: _} = task) do
    with %Task{github_repo: github_repo} = task <- task |> Repo.preload(@preloads),
         {:ok, payload} <- GitHub.Issue.create(task),
         {:ok, %GithubIssue{} = github_issue } <- IssueLinker.create_or_update_issue(github_repo, payload) do
      task |> link_with_github_changeset(github_issue) |> Repo.update
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec link_with_github_changeset(Task.t, GithubIssue.t) :: Changeset.t
  defp link_with_github_changeset(%Task{} = task, %GithubIssue{} = github_issue) do
    task |> Changeset.change(%{github_issue: github_issue})
  end

  @spec update_on_github(Task.t) :: {:ok, Task.t} :: {:error, GitHub.api_error_struct}
  defp update_on_github(%Task{github_repo_id: nil} = task), do: {:ok, task}
  defp update_on_github(%Task{github_repo_id: _} = task) do
    with %Task{github_repo: github_repo} = task <- task |> Repo.preload(@preloads),
         {:ok, payload} <- GitHub.Issue.update(task),
         {:ok, %GithubIssue{} } <- IssueLinker.create_or_update_issue(github_repo, payload) do
      {:ok, task}
    else
      {:error, github_error} -> {:error, github_error}
    end
  end
end