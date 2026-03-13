/**
 * A class that manages multiple TriggerableQueues and can broadcast to all of them.
 */
class TriggerableQueueBroadcaster #(type T = logic);
    TriggerableQueue#(T) managed_queues[$];

    // Registers a new queue for broadcasting.
    function void add_queue(ref TriggerableQueue#(T) q);
        managed_queues.push_back(q);
    endfunction

    // Pushes an element to the front of all managed queues.
    task automatic push(T item);
        foreach (managed_queues[idx]) begin
            managed_queues[idx].push(item);
        end
    endtask
endclass