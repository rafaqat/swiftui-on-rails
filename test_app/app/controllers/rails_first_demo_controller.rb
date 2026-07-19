# frozen_string_literal: true

class RailsFirstDemoController < ApplicationController
  DEMO_VERSION = 2
  MAX_TODO_LENGTH = 120
  MAX_TODO_BYTES = 160
  MAX_TODOS = 8
  MAX_SEARCH_LENGTH = 80
  MAX_ACTIVITY_ITEMS = 4
  MAX_ACTIVITY_DETAIL_LENGTH = 96
  MAX_ACTIVITY_DETAIL_BYTES = 112
  MAX_COUNTER_VALUE = 9_999
  TODO_ID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  PRODUCTS = [
    {
      id: "rails-handbook",
      name: "Rails Architecture Handbook",
      price: 34,
      category: "books",
      description: "Patterns for maintainable controllers, jobs, and boundaries.",
      accent: "from-rose-500 to-orange-400"
    },
    {
      id: "turbo-field-guide",
      name: "Turbo Field Guide",
      price: 24,
      category: "books",
      description: "A practical guide to frames, streams, and progressive enhancement.",
      accent: "from-sky-500 to-cyan-400"
    },
    {
      id: "hotwire-workshop",
      name: "Hotwire Workshop",
      price: 129,
      category: "courses",
      description: "Build a production workflow with Turbo and semantic Rails actions in one afternoon.",
      accent: "from-violet-500 to-fuchsia-400"
    },
    {
      id: "testing-clinic",
      name: "Rails Testing Clinic",
      price: 89,
      category: "courses",
      description: "Turn brittle suites into fast, confidence-building feedback loops.",
      accent: "from-emerald-500 to-teal-400"
    },
    {
      id: "deploy-checklist",
      name: "Deployment Checklist",
      price: 12,
      category: "tools",
      description: "A reusable launch checklist for secure Rails releases.",
      accent: "from-amber-500 to-yellow-400"
    },
    {
      id: "incident-cards",
      name: "Incident Response Cards",
      price: 18,
      category: "tools",
      description: "Pocket-sized prompts for calm, auditable incident response.",
      accent: "from-slate-600 to-slate-400"
    }
  ].freeze

  PRODUCT_CATEGORIES = %w[all books courses tools].freeze

  def index
    initialize_demo_state
    assign_dashboard_state(search: params[:search], category: params[:category])
  end

  def increment_counter
    initialize_demo_state
    current_counter = Integer(session[:demo_counter], exception: false) || 0
    session[:demo_counter] = [[current_counter, 0].max + 1, MAX_COUNTER_VALUE].min
    record_activity("Counter advanced", "The server handled another state-changing request.")
    assign_dashboard_state

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("rails-counter", partial: "rails_first_demo/counter", locals: { counter: @counter }),
          turbo_stream.replace("workspace-metrics", partial: "rails_first_demo/metrics", locals: metrics_locals),
          turbo_stream.replace("recent-activity", partial: "rails_first_demo/activity", locals: { activities: @activities })
        ]
      end
      format.html { redirect_to rails_first_demo_path, status: :see_other }
    end
  end

  def add_todo
    initialize_demo_state
    text, error = validated_todo_text(params[:todo_text])

    if error
      return render_invalid_todo_form(error, text)
    end

    todos = read_todos
    if todos.length >= MAX_TODOS
      return render_invalid_todo_form("This demo workspace holds up to #{MAX_TODOS} tasks.", text)
    end

    todos << { "id" => SecureRandom.uuid, "text" => text, "completed" => false }
    write_todos(todos)
    record_activity("Task added", text)
    respond_after_todo_change(form_value: "")
  end

  def toggle_todo
    initialize_demo_state
    todo, todos = find_todo(params[:id])
    return render_todo_not_found unless todo

    todo["completed"] = !todo["completed"]
    write_todos(todos)
    state = todo["completed"] ? "completed" : "reopened"
    record_activity("Task #{state}", todo["text"])
    respond_after_todo_change
  end

  def update_todo
    initialize_demo_state
    todo, todos = find_todo(params[:id])
    return render_todo_not_found unless todo

    text, error = validated_todo_text(params[:todo_text])
    if error
      return render_invalid_todo_update(todo["id"], error, text)
    end

    previous_text = todo["text"]
    todo["text"] = text
    write_todos(todos)
    record_activity("Task renamed", "#{previous_text} → #{text}")
    respond_after_todo_change
  end

  def delete_todo
    initialize_demo_state
    todo, todos = find_todo(params[:id])
    return render_todo_not_found unless todo

    write_todos(todos.reject { |candidate| candidate["id"] == todo["id"] })
    record_activity("Task removed", todo["text"])
    respond_after_todo_change
  end

  def search
    initialize_demo_state
    assign_dashboard_state(search: params[:search], category: params[:category])

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "rails-products",
          partial: "rails_first_demo/products",
          locals: products_locals
        )
      end
      format.html do
        redirect_to rails_first_demo_path(search: @search_query, category: @selected_category), status: :see_other
      end
    end
  end

  private

  def initialize_demo_state
    return if session[:rails_first_demo_version] == DEMO_VERSION

    session[:rails_first_demo_version] = DEMO_VERSION
    session[:demo_counter] = 0
    session[:demo_todos] = [
      { "id" => SecureRandom.uuid, "text" => "Map the customer onboarding flow", "completed" => true },
      { "id" => SecureRandom.uuid, "text" => "Review the Turbo Stream update path", "completed" => false },
      { "id" => SecureRandom.uuid, "text" => "Ship the workspace accessibility pass", "completed" => false }
    ]
    session[:demo_activity] = [
      activity_entry("Workspace ready", "Session-backed demo data was initialized.")
    ]
  end

  def assign_dashboard_state(search: nil, category: nil)
    @counter = [[Integer(session[:demo_counter], exception: false) || 0, 0].max, MAX_COUNTER_VALUE].min
    @todos = read_todos
    @activities = read_activities
    @metrics = calculate_metrics(@todos)
    @search_query = normalized_search(search)
    @selected_category = normalized_category(category)
    @products = filter_products(@search_query, @selected_category)
  end

  def validated_todo_text(raw_text)
    return ["", "Enter a task before adding it."] unless raw_text.is_a?(String)

    text = raw_text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").squish
    return [text, "Enter a task before adding it."] if text.blank?
    return [text, "Keep tasks to #{MAX_TODO_LENGTH} characters or fewer."] if text.length > MAX_TODO_LENGTH
    return [text, "Shorten this task so it fits safely in the browser session."] if text.bytesize > MAX_TODO_BYTES

    [text, nil]
  end

  def normalized_search(raw_search)
    return "" unless raw_search.is_a?(String)

    raw_search.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").squish.first(MAX_SEARCH_LENGTH)
  end

  def normalized_category(raw_category)
    category = raw_category.is_a?(String) ? raw_category : ""
    PRODUCT_CATEGORIES.include?(category) ? category : "all"
  end

  def filter_products(query, category)
    normalized_query = query.downcase

    PRODUCTS.select do |product|
      category_match = category == "all" || product[:category] == category
      search_match = normalized_query.blank? || [product[:name], product[:description], product[:category]].any? do |value|
        value.downcase.include?(normalized_query)
      end
      category_match && search_match
    end
  end

  def read_todos
    Array(session[:demo_todos]).first(MAX_TODOS).filter_map do |todo|
      id = value_from(todo, "id").to_s
      text = value_from(todo, "text").to_s
      next unless TODO_ID_PATTERN.match?(id) && text.present? && text.length <= MAX_TODO_LENGTH && text.bytesize <= MAX_TODO_BYTES

      { "id" => id, "text" => text, "completed" => value_from(todo, "completed") == true }
    end
  end

  def write_todos(todos)
    session[:demo_todos] = todos.map(&:dup)
  end

  def find_todo(raw_id)
    id = raw_id.to_s
    return [nil, []] unless TODO_ID_PATTERN.match?(id)

    todos = read_todos
    [todos.find { |todo| todo["id"] == id }, todos]
  end

  def read_activities
    Array(session[:demo_activity]).first(MAX_ACTIVITY_ITEMS).filter_map do |activity|
      id = value_from(activity, "id").to_s
      title = value_from(activity, "title").to_s
      next if id.blank? || title.blank?

      {
        "id" => id,
        "title" => title,
        "detail" => value_from(activity, "detail").to_s,
        "occurred_at" => value_from(activity, "occurred_at").to_s
      }
    end
  end

  def record_activity(title, detail)
    activities = read_activities
    activities.unshift(activity_entry(title, detail))
    session[:demo_activity] = activities.first(MAX_ACTIVITY_ITEMS)
  end

  def activity_entry(title, detail)
    {
      "id" => SecureRandom.uuid,
      "title" => bounded_session_text(title, max_characters: 40, max_bytes: 64),
      "detail" => bounded_session_text(
        detail,
        max_characters: MAX_ACTIVITY_DETAIL_LENGTH,
        max_bytes: MAX_ACTIVITY_DETAIL_BYTES
      ),
      "occurred_at" => Time.current.strftime("%H:%M:%S")
    }
  end

  def value_from(hash, key)
    hash.respond_to?(:[]) ? (hash[key] || hash[key.to_sym]) : nil
  end

  def bounded_session_text(value, max_characters:, max_bytes:)
    output = +""
    value.to_s.each_char do |character|
      break if output.length >= max_characters || output.bytesize + character.bytesize > max_bytes

      output << character
    end
    output
  end

  def calculate_metrics(todos)
    completed = todos.count { |todo| todo["completed"] }
    total = todos.length

    {
      total: total,
      completed: completed,
      active: total - completed,
      progress: total.zero? ? 0 : ((completed.to_f / total) * 100).round
    }
  end

  def metrics_locals
    { metrics: @metrics, counter: @counter }
  end

  def products_locals
    {
      products: @products,
      search_query: @search_query,
      selected_category: @selected_category,
      categories: PRODUCT_CATEGORIES
    }
  end

  def respond_after_todo_change(form_value: nil)
    assign_dashboard_state

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: todo_streams(form_value: form_value)
      end
      format.html { redirect_to rails_first_demo_path, status: :see_other }
    end
  end

  def render_invalid_todo_form(error, value)
    assign_dashboard_state
    @todo_form_error = error
    @todo_form_value = value

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "todo-form",
          partial: "rails_first_demo/todo_form",
          locals: { error: error, value: value }
        ), status: :unprocessable_entity
      end
      format.html { render :index, status: :unprocessable_entity }
    end
  end

  def render_invalid_todo_update(todo_id, error, value)
    assign_dashboard_state
    @todo_edit_errors = { todo_id => error }
    @todo_edit_values = { todo_id => value }

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "rails-todos",
          partial: "rails_first_demo/todos",
          locals: {
            todos: @todos,
            edit_errors: @todo_edit_errors,
            edit_values: @todo_edit_values
          }
        ), status: :unprocessable_entity
      end
      format.html { render :index, status: :unprocessable_entity }
    end
  end

  def render_todo_not_found
    respond_to do |format|
      format.turbo_stream { head :not_found }
      format.html { render plain: "Task not found", status: :not_found }
    end
  end

  def todo_streams(form_value: nil)
    [
      turbo_stream.replace(
        "rails-todos",
        partial: "rails_first_demo/todos",
        locals: { todos: @todos, edit_errors: {}, edit_values: {} }
      ),
      turbo_stream.replace(
        "todo-form",
        partial: "rails_first_demo/todo_form",
        locals: { error: nil, value: form_value }
      ),
      turbo_stream.replace("workspace-metrics", partial: "rails_first_demo/metrics", locals: metrics_locals),
      turbo_stream.replace(
        "recent-activity",
        partial: "rails_first_demo/activity",
        locals: { activities: @activities }
      )
    ]
  end
end
