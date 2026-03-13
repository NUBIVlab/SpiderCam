/**
 * Class that manages a queue with an event trigger whenever an item is added or removed.
 */
class TriggerableQueue #(type T = logic);
    T queue[$];
    event element_added_event;
    event element_removed_event;

    // Inserts an element at the beginning of the queue and triggers the addition event.
    task push(T item);
        queue.push_front(item);
        ->element_added_event;
    endtask

    // Waits until the queue has data, then removes the last element and triggers the removal event.
    task pop(output T item);
        while (queue.size() == 0) @(element_added_event);
        item = queue.pop_back();
        ->element_removed_event;
    endtask

    function automatic logic isempty();
        return (queue.size() == 0);
    endfunction
endclass