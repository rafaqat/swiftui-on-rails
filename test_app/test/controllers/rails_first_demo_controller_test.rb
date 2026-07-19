# frozen_string_literal: true

require "test_helper"

class RailsFirstDemoControllerTest < ActionDispatch::IntegrationTest
  TURBO_HEADERS = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  test "renders a complete workspace with valid session-backed tasks" do
    get rails_first_demo_path

    assert_response :success
    assert_select "main", count: 1
    assert_select "h1", text: "Rails-first workspace"
    assert_select "#workspace-metrics [role='progressbar'][aria-valuenow='33']"
    assert_select "#rails-todos li", count: 3
    assert_select "#rails-products article", count: RailsFirstDemoController::PRODUCTS.length
    assert_select "#recent-activity", text: /Workspace ready/
    assert_select "#rails-todos .line-through.text-slate-600", count: 1
    assert_select "#rails-todos .text-emerald-700", text: "Completed", count: 1
    assert_select "#recent-activity time.text-slate-600", minimum: 1

    todo_ids.each do |id|
      assert_match RailsFirstDemoController::TODO_ID_PATTERN, id
    end
  end

  test "keeps CSRF verification on every write action" do
    before_filters = RailsFirstDemoController._process_action_callbacks
      .select { |callback| callback.kind == :before }
      .map(&:filter)

    assert_includes before_filters, :verify_authenticity_token
  end

  test "creates toggles renames and deletes a task through HTML fallbacks" do
    get rails_first_demo_path

    post rails_first_demo_add_todo_path, params: { todo_text: "  Prepare   launch brief  " }
    assert_response :see_other
    follow_redirect!

    created_id = todo_id_for("Prepare launch brief")
    assert_match RailsFirstDemoController::TODO_ID_PATTERN, created_id

    patch toggle_rails_first_demo_todo_path(created_id)
    assert_response :see_other
    follow_redirect!
    assert_select "#todo-#{created_id} .line-through", text: "Prepare launch brief"

    patch update_rails_first_demo_todo_path(created_id), params: { todo_text: "Publish launch brief" }
    assert_response :see_other
    follow_redirect!
    assert_select "#todo-#{created_id}", text: /Publish launch brief/
    assert_select "#recent-activity", text: /Task renamed/

    delete delete_todo_path(created_id)
    assert_response :see_other
    follow_redirect!
    assert_select "#todo-#{created_id}", count: 0
    assert_select "#recent-activity", text: /Task removed/
  end

  test "returns targeted Turbo Streams for task and counter changes" do
    get rails_first_demo_path

    post rails_first_demo_add_todo_path,
      params: { todo_text: "Verify stream targets" },
      headers: TURBO_HEADERS

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action='replace'][target='rails-todos']"
    assert_select "turbo-stream[action='replace'][target='todo-form']"
    assert_select "turbo-stream[action='replace'][target='workspace-metrics']"
    assert_select "turbo-stream[action='replace'][target='recent-activity']"
    assert_includes response.body, "Verify stream targets"

    post rails_first_demo_increment_counter_path, headers: TURBO_HEADERS

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='rails-counter']"
    assert_select "turbo-stream[action='replace'][target='workspace-metrics']"
    assert_select "turbo-stream[action='replace'][target='recent-activity']"
    assert_select "turbo-stream[target='rails-counter'] template", text: /1/
  end

  test "rejects blank and overlong tasks without changing the queue" do
    get rails_first_demo_path
    original_ids = todo_ids

    post rails_first_demo_add_todo_path,
      params: { todo_text: "   " },
      headers: TURBO_HEADERS

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='todo-form'] [role='alert']", text: "Enter a task before adding it."

    post rails_first_demo_add_todo_path,
      params: { todo_text: "x" * (RailsFirstDemoController::MAX_TODO_LENGTH + 1) }

    assert_response :unprocessable_entity
    assert_select "[role='alert']", text: /characters or fewer/

    post rails_first_demo_add_todo_path,
      params: { todo_text: "🧪" * ((RailsFirstDemoController::MAX_TODO_BYTES / 4) + 1) },
      headers: TURBO_HEADERS

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='todo-form'] [role='alert']", text: /fits safely in the browser session/

    get rails_first_demo_path
    assert_response :success
    assert_equal original_ids, todo_ids
  end

  test "treats structured values as invalid instead of coercing them into task or search text" do
    get rails_first_demo_path

    post rails_first_demo_add_todo_path,
      params: { todo_text: { nested: "unexpected" } },
      headers: TURBO_HEADERS

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='todo-form'] [role='alert']", text: /Enter a task/

    post rails_first_demo_search_path,
      params: { search: ["rails"], category: { nested: "books" } },
      headers: TURBO_HEADERS

    assert_response :success
    assert_select "turbo-stream[target='rails-products'] article", count: RailsFirstDemoController::PRODUCTS.length
    assert_select "turbo-stream[target='rails-products'] option[value='all'][selected='selected']"
  end

  test "bounds session-backed tasks before the cookie can grow without limit" do
    get rails_first_demo_path

    (RailsFirstDemoController::MAX_TODOS - todo_ids.length).times do |index|
      suffix = index.to_s
      task = ("x" * (RailsFirstDemoController::MAX_TODO_LENGTH - suffix.length)) + suffix
      post rails_first_demo_add_todo_path, params: { todo_text: task }
      assert_response :see_other
    end

    post rails_first_demo_add_todo_path,
      params: { todo_text: "One task too many" },
      headers: TURBO_HEADERS

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='todo-form'] [role='alert']", text: /up to #{RailsFirstDemoController::MAX_TODOS} tasks/
  end

  test "preserves invalid edit input and rejects unknown task identifiers" do
    get rails_first_demo_path
    existing_id = todo_ids.first

    patch update_rails_first_demo_todo_path(existing_id),
      params: { todo_text: "x" * (RailsFirstDemoController::MAX_TODO_LENGTH + 1) },
      headers: TURBO_HEADERS

    assert_response :unprocessable_entity
    assert_select "turbo-stream[target='rails-todos'] [role='alert']", text: /characters or fewer/
    assert_select "turbo-stream[target='rails-todos'] details[open]"

    patch toggle_rails_first_demo_todo_path(SecureRandom.uuid), headers: TURBO_HEADERS
    assert_response :not_found

    delete delete_todo_path("not-a-task-id")
    assert_response :not_found
    assert_equal "Task not found", response.body
  end

  test "escapes task content instead of rendering submitted markup" do
    get rails_first_demo_path

    post rails_first_demo_add_todo_path,
      params: { todo_text: "<script>window.bad = true</script>" },
      headers: TURBO_HEADERS

    assert_response :success
    assert_select "script", count: 0
    assert_includes response.body, "&lt;script&gt;window.bad = true&lt;/script&gt;"
  end

  test "searches and filters products while normalizing bounded inputs" do
    get rails_first_demo_path

    post rails_first_demo_search_path,
      params: { search: "rails", category: "books" },
      headers: TURBO_HEADERS

    assert_response :success
    assert_select "turbo-stream[action='replace'][target='rails-products']"
    assert_select "#product-rails-handbook"
    assert_select "#product-turbo-field-guide", count: 0
    assert_select "#product-hotwire-workshop", count: 0
    assert_select "option[value='books'][selected='selected']"

    long_search = "testing" + ("x" * 200)
    post rails_first_demo_search_path, params: { search: long_search, category: "../../admin" }

    assert_response :see_other
    follow_redirect!
    assert_select "input[name='search']" do |inputs|
      assert_equal RailsFirstDemoController::MAX_SEARCH_LENGTH, inputs.first["value"].length
    end
    assert_select "option[value='all'][selected='selected']"
  end

  test "renders an empty state after all tasks are removed" do
    get rails_first_demo_path

    todo_ids.each do |todo_id|
      delete delete_todo_path(todo_id)
      assert_response :see_other
    end
    follow_redirect!

    assert_select "#rails-todos", text: /Queue cleared/
    assert_select "#workspace-metrics [role='progressbar'][aria-valuenow='0']"
  end

  private

  def todo_ids
    css_select("#rails-todos li[id^='todo-']").map { |item| item["id"].delete_prefix("todo-") }
  end

  def todo_id_for(text)
    item = css_select("#rails-todos li[id^='todo-']").find { |candidate| candidate.text.include?(text) }
    item&.[]( "id" )&.delete_prefix("todo-")
  end
end
