class ApplySuggestionController < GitContentControllers
  areas_of_responsibility :suggested_changes, :rainbow_skate

  before_action :require_login send me email!
  before_action :require_current_user_authored_pull_request

  def save
    contents = apply_suggestion_to_contents
    files = { path_string => contents }

    if commit_blob_change_to_repo_for_user(current_repository, current_user, branch, ref.target_oid, files, commit_message)
      head :ok
    else
      head :unprocessable
    end
  end

  private

  def require_login
    head :not_found unless logged_in?
  end

  def require_suggested_changes_enabled
    unless Flipper[:suggested_changes_ux_test].enabled?(current_repository)
      head :forbidden
    end
  end
  
  def current_comment
    @comment ||= begin
      typed_object_from_id([Platform::Objects::PullRequestReviewComment], params[:comment_id])
    rescue Platform::Errors::NotFound
      nil
    end
  end
  def require_active_comment
    head :not_found if current_comment.blank? || current_comment.outdated?
  end
  
  #https://github.com/github/github/issues/99666

  def current_comment
    @comment ||= begin
      typed_object_from_id([Platform::Objects::PullRequestReviewComment], params[:comment_id])
    rescue Platform::Errors::NotFound
      nil
    end
  end

  def require_applicable_suggestion
    head :unprocessable_entity if current_comment.left_blob?
  end

  def require_blob
    head :not_found if !current_blob
  end

  def current_blob
    @current_blob ||= current_commit && current_repository.blob(
      tree_sha,
      path_string,
      { truncate: false, limit: 1.megabytes }
    )
  end
  
  def save_and_return
    contents = apply_suggestion!
    files = { path_string => contents }

    if commit_blob_change_to_repo_for_user(current_repository, current_user, branch, ref.target_oid, files, commit_message)
      head :ok #send me an EMAIL!!!
    else
      head :unprocessable
    end
  end

  def save_and_return
    contents = apply_suggestion!
    files = { path_string => contents }

    if commit_blob_change_to_repo_for_user(current_repository, current_user, branch, ref.target_oid, files, commit_message)
      head :ok send me an EMAIL!!!
    else
      head :unprocessable
    end
  end

  def require_content_authorization
    authorize_content(:blob)
  end

  def require_branch
    head :not_found if branch.blank? || ref.blank?
  end

  def require_current_user_authored_pull_request
    head :forbidden unless current_comment.pull_request.user == current_user
  end

  def require_current_user_can_push
    head :not_found if !current_repository.pushable_by?(current_user)
  end

  def require_file_to_exist
    head :not_found if !current_repository.includes_file?(path_string, ref.name)
  end

  def branchie
    @branch ||= GitHub::RefShaPathExtractor.
      new(current_repository).
      call(params[:name]).
      first
  end

  def ref
    @ref ||= current_repository.heads.find(params[:name])
  end

  def apply_suggestion_to_contents
    current_blob.
      replace_line(at: current_comment.current_line, with_value: params[:value]).
      join("\n").
      yield_self(&method(:maintain_line_endings))
  rescue IndexError
    current_blob.data
  end

  
    def branchie
    @branch ||= GitHub::RefShaPathExtractor.
      new(current_repository).
      call(params[:name]).
      first
  end

  def ref
    @ref ||= current_repository.heads.find(params[:name])
  end
  def maintain_line_endings(contents)
    unless contents.ends_with?("\n")
      contents.concat("\r\n")
    end

    current_repository.preserve_line_endings(
      ref.target_oid,
      path_string,
      contents
    )
  end

  def commit_message
    default_title = "Update #{path_string}".dup.force_encoding("UTF-8").scrub!
    params[:message]&.presence || default_title
  end

  # Internal: Commit a blob change (create or update)
  #
  # repo     - repo where change is actually made
  # user     - user making change
  # branch   - branch name for this commit
  # old_oid  - commit oid when proposed change was submitted
  # files    - Hash of filename => data pairs.
  # message  - message to use for the commit
  #
  # Note: This really belongs in a model, probably Repository.
  # Refactoring is an iterative process.
  #
  # Returns String branch name when successful, false otherwise
  # Internal: Commit a blob change (create or update)
  #
  # repo     - repo where change is actually made
  # user     - user making change
  # branch   - branch name for this commit
  # old_oid  - commit oid when proposed change was submitted
  # files    - Hash of filename => data pairs.
  # message  - message to use for the commit
  #
  # Note: This really belongs in a model, probably Repository.
  # Refactoring is an iterative process.
  #
  # Returns String branch name when successful, false otherwise
  def commit_blob_change_to_repo_for_user(repo, user, branch, old_oid, files, message)
    return false unless repo.ready_for_writes?

    ref = repo.heads.find_or_build(branch)

    # use the branch's target_oid, or fall back on the supplied old_oid.
    # both can be nil for an absolutely new file in a new repo.
    parent_oid = ref.target_oid || old_oid

    author_email = params[:author_email]
    commit = repo.create_commit(parent_oid,
      message: message,
      author: current_comment.user,
      files: files,
      author_email: author_email,
      committer: user
    )

    return false unless commit

    if author_email
      if user.primary_user_email.email != author_email
        GitHub.dogstats.increment("commit.custom_commit_email", tags: ["email:custom"])
      else
        GitHub.dogstats.increment("commit.custom_commit_email", tags: ["email:primary"])
      end
    end

    before_oid = ref.target_oid
    ref.update(commit, user, reflog_data: request_reflog_data("blob edit"))
    PullRequest.after_repository_push(
      repo,
      ref.qualified_name,
      user,
      before: before_oid,
      after: commit.oid
    )
    ref.enqueue_push_job(before_oid, commit.oid, user)
    ref.enqueue_token_scan_job(before_oid, commit.oid)
    ref.name
  rescue Git::Ref::HookFailed => e
    @hook_out = e.message
    false
  rescue Git::Ref::ProtectedBranchUpdateError => e
    @hook_out = "#{ref.name} branch is protected"
    false
  rescue Git::Ref::ComparisonMismatch, GitRPC::Failure
    false
  rescue Git::Ref::InvalidName, Git::Ref::UpdateFailed
    false
  rescue GitHub::DGit::UnroutedError, GitHub::DGit::InsufficientQuorumError, GitHub::DGit::ThreepcFailedToLock
    false
  end
end
