/*
 * Encapsulates an image
 */

class Image #(
    parameter DATA_WIDTH   = 0,
    parameter IMAGE_WIDTH  = 0,
    parameter IMAGE_HEIGHT = 0
);
    logic [DATA_WIDTH - 1 : 0] image [IMAGE_HEIGHT][IMAGE_WIDTH];
    string file_path;
    int data_width;
    int width;
    int height;
    logic [15:0] col_center;
    logic [15:0] row_center;
    
    function new();
        this.data_width  = DATA_WIDTH;
        this.width       = IMAGE_WIDTH;
        this.height      = IMAGE_HEIGHT;
    endfunction

    function void generate_random_image();
        for(int r = 0; r < IMAGE_HEIGHT; r++) begin
            for(int c = 0; c < IMAGE_WIDTH; c++) begin
                this.image[r][c] = $urandom;
            end
        end
    endfunction

    function void generate_constant_image(int constant);
        for(int r = 0; r < IMAGE_HEIGHT; r++) begin
            for(int c = 0; c < IMAGE_WIDTH; c++) begin
                this.image[r][c] = constant;
            end
        end
    endfunction

    function void generate_increasing_image();
        int i = 0;
        for(int r = 0; r < IMAGE_HEIGHT; r++) begin
            for(int c = 0; c < IMAGE_WIDTH; c++) begin
                this.image[r][c] = r + c;
            end
        end
    endfunction 

    function int generate_image_from_ppm();
        int file, r, g, b, width, height, maxval;
        string magic_num;
        string unique_filename;
        string num;
            
        // open the file 
        file = $fopen(this.file_path, "r");
        if(file == 0) begin
            $display("ERROR: Failed to open file %s", this.file_path);
            return -1;
        end

        // Read PPM header (magic number, width, height, maxval)
        // %s reads the string (P3)
        // %d reads integers (width, height, max color value)
        $fscanf(file, "%s\n%d %d\n%d\n", magic_num, width, height, maxval);

        if (magic_num != "P3") begin
            $display("ERROR: Unsupported PPM format (only ASCII P3 supported).");
            $fclose(file);
            return -1;
        end

        for (int y = 0; y < this.height; y++) begin
            for (int x = 0; x < this.width; x++) begin
                // Read the red, green and the blue values
                $fscanf(file, "%d\n %d\n %d\n", r, g, b);
                // just use green for monochrome
                this.image[y][x] = g;
            end
        end

        $fclose(file);
        return 0;
    endfunction

    function int generate_ppm_from_image();
        // Try to open the file_path for writing.
        int file = $fopen(this.file_path, "w");
        if (file == 0) begin
            $display("Error: Could not open file %s for writing.", this.file_path);
            return -1;
        end

        // Write ppm header
        $fdisplay(file, "P3");
        $fdisplay(file, "%0d %0d", width, height);
        $fdisplay(file, "%0d", (1 << DATA_WIDTH) - 1);

        // Write pixel data
        for(int y = 0; y < IMAGE_HEIGHT; y++) begin
            for(int x = 0; x < IMAGE_WIDTH; x++) begin
                // Since the image is monochrome, we repeat the value for R, G, B channels
                int pixel_value = image[y][x];
                $fdisplay(file, "%0d %0d %0d", pixel_value, pixel_value, pixel_value);
            end
        end

        // Close the file and return
        $fclose(file);
        return 0;
    endfunction

    function void print();
        $display();
        for(int r = 0; r < IMAGE_HEIGHT; r++) begin
            for(int c = 0; c < IMAGE_WIDTH; c++) begin
                $write("%h ", image[r][c]);
            end
            $display();
        end
        $display();
    endfunction   

    function void print_32();
        $display();
        for(int r = 0; r < IMAGE_HEIGHT; r++) begin
            for(int c = 0; c < IMAGE_WIDTH; c++) begin
                $write("%0.4f ", $bitstoshortreal(image[r][c]));
            end
            $display();
        end
        $display();
    endfunction

    function void generate_middle_square_image(int length, int background_constant, int square_constant);
        int i = 0;
        int width_start = (IMAGE_WIDTH - length) / 2;
        int width_end   = width_start + length;
        int height_start = (IMAGE_HEIGHT - length) / 2;
        int height_end  = height_start + length;

        for(int r = 0; r < IMAGE_HEIGHT; r++) begin
            for(int c = 0; c < IMAGE_WIDTH; c++) begin
                if((r >= height_start) && (r < height_end) && (c >= width_start) && (c < width_end)) begin
                    this.image[r][c] = square_constant;
                end else begin
                    this.image[r][c] = background_constant;
                end
                
            end
        end
    endfunction 

endclass